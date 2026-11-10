import Foundation

struct RoomSummary: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: RoomID
    let anchorName: String
    let title: String
    let categoryName: String
    let popularity: Int
    let coverURL: URL?
    let avatarURL: URL?
    let isLive: Bool

    var largeCoverURL: URL? {
        guard id.platform == .douyu, let coverURL, coverURL.lastPathComponent == "dy1" else { return coverURL }
        return coverURL.deletingLastPathComponent().appending(path: "webpdy2")
    }
}

struct LiveCategory: Sendable, Equatable, Hashable, Identifiable, Codable {
    struct Source: Sendable, Hashable, Codable {
        let platform: Platform
        let id: Int
        let kind: Int

        init(platform: Platform, id: Int, kind: Int = 0) {
            self.platform = platform
            self.id = id
            self.kind = kind
        }
    }

    let name: String
    let sources: [Source]
    let liveCount: Int?
    let posterURL: URL?

    var id: String { name }
}

struct CategoryGroup: Sendable, Equatable, Identifiable {
    let name: String
    let categories: [LiveCategory]

    var id: String { name }
}

struct RoomPage: Sendable, Equatable {
    let rooms: [RoomSummary]
    let pageCount: Int
}
