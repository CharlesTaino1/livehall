enum Platform: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case douyu
    case douyin

    var id: Self { self }

    var name: String {
        switch self {
        case .douyu: "斗鱼"
        case .douyin: "抖音"
        }
    }

    var audienceLabel: String {
        switch self {
        case .douyu: "贵宾"
        case .douyin: "在线"
        }
    }
}

struct RoomID: Sendable, Hashable, Codable, CustomStringConvertible {
    let platform: Platform
    let number: Int

    init(_ platform: Platform, _ number: Int) {
        self.platform = platform
        self.number = number
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let legacy = try? container.decode(Int.self) {
            self.init(.douyu, legacy)
            return
        }
        let text = try container.decode(String.self)
        let parts = text.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let platform = Platform(rawValue: String(parts[0])), let number = Int(parts[1]) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "房间标识无法解析：\(text)")
        }
        self.init(platform, number)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String { "\(platform.rawValue):\(number)" }
}
