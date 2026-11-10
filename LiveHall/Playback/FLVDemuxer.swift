import Foundation

enum VideoCodec: Sendable, Equatable {
    case h264
    case hevc
}

struct VideoFrame: Sendable {
    let decodeTime: Int
    let compositionOffset: Int
    let isKeyframe: Bool
    let data: Data
}

struct AudioFrame: Sendable {
    let time: Int
    let data: Data
}

enum FLVEvent: Sendable {
    case videoConfig(VideoCodec, Data)
    case video(VideoFrame)
    case audioConfig(Data)
    case audio(AudioFrame)
}

enum FLVError: Error, Sendable {
    case notFLV
    case unsupportedVideoCodec
    case unsupportedAudioCodec
    case malformed
}

struct FLVDemuxer {
    private var buffer = Data()
    private var hasReadHeader = false

    private static let headerLength = 9
    private static let tagHeaderLength = 11

    mutating func append(_ chunk: Data) throws(FLVError) -> [FLVEvent] {
        buffer.append(chunk)
        var events: [FLVEvent] = []
        var consumed = 0
        var failure: FLVError?

        buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if !hasReadHeader {
                guard raw.count >= Self.headerLength + 4 else { return }
                guard raw[0] == 0x46, raw[1] == 0x4C, raw[2] == 0x56 else {
                    failure = .notFLV
                    return
                }
                let dataOffset = Int(Self.uint32(raw, 5))
                guard dataOffset >= Self.headerLength, raw.count >= dataOffset + 4 else { return }
                consumed = dataOffset + 4
                hasReadHeader = true
            }
            while raw.count - consumed >= Self.tagHeaderLength {
                let type = raw[consumed] & 0x1F
                let size = Int(Self.uint24(raw, consumed + 1))
                let tagEnd = consumed + Self.tagHeaderLength + size
                guard raw.count >= tagEnd + 4 else { break }
                let timestamp = Int(Self.uint24(raw, consumed + 4)) | Int(raw[consumed + 7]) << 24
                let payload = UnsafeRawBufferPointer(rebasing: raw[(consumed + Self.tagHeaderLength)..<tagEnd])
                do throws(FLVError) {
                    switch type {
                    case 8: try Self.audioTag(payload, timestamp, &events)
                    case 9: try Self.videoTag(payload, timestamp, &events)
                    default: break
                    }
                } catch {
                    failure = error
                    return
                }
                consumed = tagEnd + 4
            }
        }

        if let failure { throw failure }
        if consumed > 0 { buffer.removeSubrange(0..<consumed) }
        return events
    }

    private static func videoTag(
        _ p: UnsafeRawBufferPointer, _ timestamp: Int, _ events: inout [FLVEvent]
    ) throws(FLVError) {
        guard p.count >= 1 else { throw .malformed }
        let first = p[0]
        let isKeyframe: Bool
        let codec: VideoCodec
        let packetType: UInt8
        var compositionOffset = 0
        let bodyStart: Int

        if first & 0x80 != 0 {
            guard p.count >= 5 else { throw .malformed }
            isKeyframe = (first >> 4) & 0x07 == 1
            switch (p[1], p[2], p[3], p[4]) {
            case (0x68, 0x76, 0x63, 0x31): codec = .hevc
            case (0x61, 0x76, 0x63, 0x31): codec = .h264
            default: throw .unsupportedVideoCodec
            }
            switch first & 0x0F {
            case 0:
                packetType = 0
                bodyStart = 5
            case 1:
                guard p.count >= 8 else { throw .malformed }
                packetType = 1
                compositionOffset = Int(signed24(p, 5))
                bodyStart = 8
            case 3:
                packetType = 1
                bodyStart = 5
            default:
                return
            }
        } else {
            let frameType = first >> 4
            if frameType == 5 { return }
            switch first & 0x0F {
            case 7: codec = .h264
            case 12: codec = .hevc
            default: throw .unsupportedVideoCodec
            }
            guard p.count >= 5 else { throw .malformed }
            isKeyframe = frameType == 1
            packetType = p[1]
            compositionOffset = Int(signed24(p, 2))
            bodyStart = 5
        }

        let body = Data(UnsafeRawBufferPointer(rebasing: p[bodyStart...]))
        switch packetType {
        case 0:
            events.append(.videoConfig(codec, body))
        case 1:
            events.append(
                .video(
                    VideoFrame(
                        decodeTime: timestamp, compositionOffset: compositionOffset, isKeyframe: isKeyframe,
                        data: body)))
        default:
            break
        }
    }

    private static func audioTag(
        _ p: UnsafeRawBufferPointer, _ timestamp: Int, _ events: inout [FLVEvent]
    ) throws(FLVError) {
        guard p.count >= 2 else { throw .malformed }
        guard p[0] >> 4 == 10 else { throw .unsupportedAudioCodec }
        let body = Data(UnsafeRawBufferPointer(rebasing: p[2...]))
        switch p[1] {
        case 0: events.append(.audioConfig(body))
        case 1: events.append(.audio(AudioFrame(time: timestamp, data: body)))
        default: break
        }
    }

    private static func uint24(_ p: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(p[offset]) << 16 | UInt32(p[offset + 1]) << 8 | UInt32(p[offset + 2])
    }

    private static func signed24(_ p: UnsafeRawBufferPointer, _ offset: Int) -> Int32 {
        Int32(bitPattern: uint24(p, offset) << 8) >> 8
    }

    private static func uint32(_ p: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(p[offset]) << 24 | UInt32(p[offset + 1]) << 16 | UInt32(p[offset + 2]) << 8 | UInt32(p[offset + 3])
    }
}
