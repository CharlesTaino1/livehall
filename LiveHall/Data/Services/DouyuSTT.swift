import Foundation

enum DouyuSTT {
    private static let clientMessageType: UInt16 = 689

    static func pack(_ fields: [(String, String)]) -> Data {
        let body = fields.map { "\($0.0)@=\(escape($0.1))/" }.joined()
        let bytes = Array(body.utf8)
        var data = Data(capacity: bytes.count + 13)
        let length = UInt32(bytes.count + 9)
        data.append(littleEndian: length)
        data.append(littleEndian: length)
        data.append(littleEndian: clientMessageType)
        data.append(contentsOf: [0, 0])
        data.append(contentsOf: bytes)
        data.append(0)
        return data
    }

    static func unpack(_ data: Data) -> [String] {
        var messages: [String] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset + 12 <= raw.count {
                let length = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian)
                let end = offset + 4 + length
                guard length >= 9, end <= raw.count else { break }
                let body = UnsafeRawBufferPointer(rebasing: raw[(offset + 12)..<(end - 1)])
                messages.append(String(decoding: body, as: UTF8.self))
                offset = end
            }
        }
        return messages
    }

    static func parse(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body.split(separator: "/", omittingEmptySubsequences: true) {
            guard let separator = pair.range(of: "@=") else { continue }
            fields[String(pair[..<separator.lowerBound])] = unescape(String(pair[separator.upperBound...]))
        }
        return fields
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "@", with: "@A").replacingOccurrences(of: "/", with: "@S")
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "@S", with: "/").replacingOccurrences(of: "@A", with: "@")
    }
}

extension Data {
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
