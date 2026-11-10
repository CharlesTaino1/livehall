import Foundation

enum DouyinCategoryPage {
    struct Entry {
        let id: Int
        let kind: Int
        let title: String
        let subs: [Entry]
    }

    private static let chunkStart = "self.__pace_f.push([1,\""
    private static let chunkEnd = "\"])</script>"
    private static let escapedMarker = "\\\"categoryData\\\":"
    private static let marker = "\"categoryData\":"

    static func entries(in html: Data) throws(LiveError) -> [Entry] {
        guard let page = String(data: html, encoding: .utf8),
            let markerRange = page.range(of: escapedMarker),
            let startRange = page.range(
                of: chunkStart, options: .backwards, range: page.startIndex..<markerRange.lowerBound),
            let endRange = page.range(of: chunkEnd, range: markerRange.upperBound..<page.endIndex)
        else { throw .badResponse("首页里没有分区数据") }

        let literal = "\"" + page[startRange.upperBound..<endRange.lowerBound] + "\""
        guard
            let chunk = (try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed))
                as? String,
            let array = arrayJSON(after: marker, in: chunk),
            let raw = try? JSONDecoder().decode([Raw].self, from: array)
        else { throw .badResponse("分区数据无法解析") }
        return raw.compactMap(Entry.init)
    }

    private static func arrayJSON(after marker: String, in text: String) -> Data? {
        guard let range = text.range(of: marker) else { return nil }
        let bytes = Array(text[range.upperBound...].utf8)
        guard bytes.first == UInt8(ascii: "[") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for (index, byte) in bytes.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "["): depth += 1
            case UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return Data(bytes[0...index]) }
            default: break
            }
        }
        return nil
    }

    fileprivate struct Raw: Decodable {
        struct Partition: Decodable {
            let idStr: String
            let type: Int
            let title: String

            enum CodingKeys: String, CodingKey {
                case idStr = "id_str"
                case type
                case title
            }
        }
        let partition: Partition
        let subPartition: [Raw]?

        enum CodingKeys: String, CodingKey {
            case partition
            case subPartition = "sub_partition"
        }
    }
}

extension DouyinCategoryPage.Entry {
    fileprivate init?(_ raw: DouyinCategoryPage.Raw) {
        guard let id = Int(raw.partition.idStr) else { return nil }
        self.init(
            id: id, kind: raw.partition.type, title: raw.partition.title,
            subs: (raw.subPartition ?? []).compactMap(Self.init))
    }
}
