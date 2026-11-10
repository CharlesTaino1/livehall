import Compression
import Foundation

enum GzipPayload {
    private static let fixedHeaderLength = 10
    private static let trailerLength = 8

    static func inflate(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > fixedHeaderLength + trailerLength, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
            return nil
        }
        let flags = bytes[3]
        var offset = fixedHeaderLength
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { return nil }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            guard let end = bytes[offset...].firstIndex(of: 0) else { return nil }
            offset = end + 1
        }
        if flags & 0x02 != 0 { offset += 2 }
        guard offset < bytes.count - trailerLength else { return nil }
        let deflated = Data(bytes[offset..<(bytes.count - trailerLength)])
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }
}
