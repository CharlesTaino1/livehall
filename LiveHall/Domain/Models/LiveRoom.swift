import Foundation

struct LiveRoom: Sendable, Equatable, Hashable {
    let id: RoomID
    let connectionID: String
    let anchorName: String
    let avatarURL: URL?
    let title: String
    let isLive: Bool
    let categoryName: String
    let popularity: Int
    let startedAt: Date?
    let clubName: String?
}
