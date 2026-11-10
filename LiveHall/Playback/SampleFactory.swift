import AudioToolbox
import CoreMedia
import Foundation

struct VideoFormat: @unchecked Sendable {
    let description: CMVideoFormatDescription
    let lengthSize: Int
}

enum SampleError: Error, Sendable {
    case invalidConfig
    case coreMedia(OSStatus)
}

enum SampleFactory {

    static func videoFormat(codec: VideoCodec, config: Data) throws(SampleError) -> VideoFormat {
        let parsed =
            switch codec {
            case .h264: try parseAVCConfig(config)
            case .hevc: try parseHEVCConfig(config)
            }
        var format: CMVideoFormatDescription?
        let status: OSStatus = parsed.parameterSets.withContiguousPointers { pointers, sizes in
            switch codec {
            case .h264:
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: pointers.count,
                    parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: Int32(parsed.lengthSize), formatDescriptionOut: &format)
            case .hevc:
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: pointers.count,
                    parameterSetPointers: pointers, parameterSetSizes: sizes,
                    nalUnitHeaderLength: Int32(parsed.lengthSize), extensions: nil, formatDescriptionOut: &format)
            }
        }
        guard status == noErr, let format else { throw .coreMedia(status) }
        return VideoFormat(description: format, lengthSize: parsed.lengthSize)
    }

    static func videoSample(
        _ frame: VideoFrame, format: VideoFormat, pts: Int, dts: Int
    ) throws(SampleError) -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1000),
            decodeTimeStamp: CMTime(value: CMTimeValue(dts), timescale: 1000))
        let block = try blockBuffer(frame.data)
        var size = frame.data.count
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format.description,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw .coreMedia(status) }
        if !frame.isKeyframe,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    static func audioFormat(config: Data) throws(SampleError) -> (
        description: CMAudioFormatDescription, sampleRate: Int
    ) {
        let asc = try parseAudioSpecificConfig(config)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(asc.sampleRate), mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: asc.objectType, mBytesPerPacket: 0, mFramesPerPacket: 1024,
            mBytesPerFrame: 0, mChannelsPerFrame: asc.channels, mBitsPerChannel: 0, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = config.withUnsafeBytes { cookie in
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                magicCookieSize: cookie.count, magicCookie: cookie.baseAddress, extensions: nil,
                formatDescriptionOut: &format)
        }
        guard status == noErr, let format else { throw .coreMedia(status) }
        return (format, asc.sampleRate)
    }

    static func audioSample(
        _ data: Data, format: CMAudioFormatDescription, pts: CMTime
    ) throws(SampleError) -> CMSampleBuffer {
        let block = try blockBuffer(data)
        var description = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(data.count))
        var sample: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, presentationTimeStamp: pts, packetDescriptions: &description,
            sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw .coreMedia(status) }
        return sample
    }

    private static func blockBuffer(_ data: Data) throws(SampleError) -> CMBlockBuffer {
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard status == noErr, let block else { throw .coreMedia(status) }
        status = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard status == noErr else { throw .coreMedia(status) }
        return block
    }

    private struct ParsedVideoConfig {
        var lengthSize: Int
        var parameterSets: [Data]
    }

    private static func parseAVCConfig(_ c: Data) throws(SampleError) -> ParsedVideoConfig {
        var reader = ByteReader(c)
        guard c.count >= 7 else { throw .invalidConfig }
        reader.skip(4)
        let lengthSize = Int(reader.byte() & 0x03) + 1
        var sets: [Data] = []
        let spsCount = Int(reader.byte() & 0x1F)
        for _ in 0..<spsCount { sets.append(try reader.lengthPrefixed()) }
        let ppsCount = Int(reader.byte())
        for _ in 0..<ppsCount { sets.append(try reader.lengthPrefixed()) }
        guard !sets.isEmpty else { throw .invalidConfig }
        return ParsedVideoConfig(lengthSize: lengthSize, parameterSets: sets)
    }

    private static func parseHEVCConfig(_ c: Data) throws(SampleError) -> ParsedVideoConfig {
        var reader = ByteReader(c)
        guard c.count >= 23 else { throw .invalidConfig }
        reader.skip(21)
        let lengthSize = Int(reader.byte() & 0x03) + 1
        let arrayCount = Int(reader.byte())
        var sets: [Data] = []
        for _ in 0..<arrayCount {
            let type = reader.byte() & 0x3F
            let count = Int(try reader.uint16())
            for _ in 0..<count {
                let nal = try reader.lengthPrefixed()
                if (32...34).contains(type) { sets.append(nal) }
            }
        }
        guard !sets.isEmpty else { throw .invalidConfig }
        return ParsedVideoConfig(lengthSize: lengthSize, parameterSets: sets)
    }

    private struct AudioConfig {
        var objectType: UInt32
        var sampleRate: Int
        var channels: UInt32
    }

    private static let sampleRates = [
        96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350,
    ]

    private static func parseAudioSpecificConfig(_ c: Data) throws(SampleError) -> AudioConfig {
        var bits = BitReader(c)
        var objectType = bits.read(5)
        if objectType == 31 { objectType = 32 + bits.read(6) }
        let index = bits.read(4)
        let sampleRate: Int
        if index == 15 {
            sampleRate = Int(bits.read(24))
        } else if Int(index) < sampleRates.count {
            sampleRate = sampleRates[Int(index)]
        } else {
            throw .invalidConfig
        }
        let channelConfig = bits.read(4)
        let channels: UInt32 = channelConfig == 7 ? 8 : channelConfig
        guard bits.isValid, channels > 0, sampleRate > 0 else { throw .invalidConfig }
        return AudioConfig(objectType: objectType, sampleRate: sampleRate, channels: channels)
    }
}

extension Array where Element == Data {
    fileprivate func withContiguousPointers<R>(
        _ body: ([UnsafePointer<UInt8>], [Int]) -> R
    ) -> R {
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: Swift.max(1, reduce(0) { $0 + $1.count }))
        defer { storage.deallocate() }
        var pointers: [UnsafePointer<UInt8>] = []
        var offset = 0
        for data in self {
            _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: storage + offset, count: data.count))
            pointers.append(UnsafePointer(storage + offset))
            offset += data.count
        }
        return body(pointers, map(\.count))
    }
}

private struct ByteReader {
    private let data: Data
    private var position: Int

    init(_ data: Data) {
        self.data = data
        position = data.startIndex
    }

    mutating func skip(_ count: Int) { position += count }

    mutating func byte() -> UInt8 {
        defer { position += 1 }
        return position < data.endIndex ? data[position] : 0
    }

    mutating func uint16() throws(SampleError) -> UInt16 {
        guard position + 2 <= data.endIndex else { throw .invalidConfig }
        defer { position += 2 }
        return UInt16(data[position]) << 8 | UInt16(data[position + 1])
    }

    mutating func lengthPrefixed() throws(SampleError) -> Data {
        let length = Int(try uint16())
        guard position + length <= data.endIndex else { throw .invalidConfig }
        defer { position += length }
        return Data(data[position..<(position + length)])
    }
}

private struct BitReader {
    private let data: Data
    private var bitPosition = 0
    private(set) var isValid = true

    init(_ data: Data) { self.data = data }

    mutating func read(_ count: Int) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<count {
            let byteIndex = data.startIndex + bitPosition / 8
            guard byteIndex < data.endIndex else {
                isValid = false
                return 0
            }
            value = value << 1 | UInt32((data[byteIndex] >> (7 - UInt8(bitPosition % 8))) & 1)
            bitPosition += 1
        }
        return value
    }
}
