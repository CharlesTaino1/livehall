import Foundation

struct ProtobufMessage {
    private enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    private var fields: [(number: Int, value: Value)] = []

    init?(_ data: Data) {
        var reader = Reader(data: data)
        while !reader.isAtEnd {
            guard let key = reader.varint() else { return nil }
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = reader.varint() else { return nil }
                fields.append((number, .varint(value)))
            case 1:
                guard reader.skip(8) else { return nil }
            case 2:
                guard let length = reader.varint(), let bytes = reader.take(Int(length)) else { return nil }
                fields.append((number, .bytes(bytes)))
            case 5:
                guard reader.skip(4) else { return nil }
            default:
                return nil
            }
        }
    }

    func varint(_ number: Int) -> UInt64? {
        for field in fields where field.number == number {
            if case .varint(let value) = field.value { return value }
        }
        return nil
    }

    func bytes(_ number: Int) -> Data? {
        for field in fields where field.number == number {
            if case .bytes(let value) = field.value { return value }
        }
        return nil
    }

    func string(_ number: Int) -> String? {
        bytes(number).flatMap { String(data: $0, encoding: .utf8) }
    }

    func repeatedBytes(_ number: Int) -> [Data] {
        fields.compactMap { field in
            guard field.number == number, case .bytes(let value) = field.value else { return nil }
            return value
        }
    }

    func message(_ number: Int) -> ProtobufMessage? {
        bytes(number).flatMap { ProtobufMessage($0) }
    }

    private struct Reader {
        let data: Data
        var index: Data.Index

        init(data: Data) {
            self.data = data
            index = data.startIndex
        }

        var isAtEnd: Bool { index >= data.endIndex }

        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < data.endIndex, shift < 64 {
                let byte = data[index]
                index = data.index(after: index)
                result |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        mutating func skip(_ count: Int) -> Bool {
            take(count) != nil
        }

        mutating func take(_ count: Int) -> Data? {
            guard count >= 0, data.distance(from: index, to: data.endIndex) >= count else { return nil }
            let end = data.index(index, offsetBy: count)
            defer { index = end }
            return data[index..<end]
        }
    }
}

struct ProtobufWriter {
    private(set) var data = Data()

    mutating func write(_ number: Int, varint value: UInt64) {
        appendVarint(UInt64(number << 3))
        appendVarint(value)
    }

    mutating func write(_ number: Int, bytes value: Data) {
        appendVarint(UInt64(number << 3 | 2))
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    mutating func write(_ number: Int, string value: String) {
        write(number, bytes: Data(value.utf8))
    }

    private mutating func appendVarint(_ value: UInt64) {
        var rest = value
        while rest >= 0x80 {
            data.append(UInt8(rest & 0x7f) | 0x80)
            rest >>= 7
        }
        data.append(UInt8(rest))
    }
}
