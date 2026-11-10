import Foundation

struct FollowedAnchor: Sendable, Equatable, Hashable, Codable, Identifiable {
    let roomID: RoomID
    let anchorName: String
    let avatarURL: URL?
    let followedAt: Date

    var id: RoomID { roomID }
}

struct WatchRecord: Sendable, Equatable, Hashable, Codable {
    let roomID: RoomID
    let watchedAt: Date
}

struct Library: Sendable, Equatable, Codable {
    var follows: [FollowedAnchor] = []
    var recents: [WatchRecord] = []

    func isFollowing(_ roomID: RoomID) -> Bool {
        follows.contains { $0.roomID == roomID }
    }
}
