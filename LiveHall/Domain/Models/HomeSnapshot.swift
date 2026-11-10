import Foundation

struct HomeSnapshot: Sendable, Equatable, Codable {
    struct CategoryRoomList: Sendable, Equatable, Codable {
        let category: LiveCategory
        let rooms: [RoomSummary]
    }

    let savedAt: Date
    let billboard: RoomSummary?
    let followingLive: [RoomSummary]
    let recents: [RoomSummary]
    let categoryRows: [CategoryRoomList]
}
