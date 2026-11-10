import Foundation

struct LibraryRepository: Sendable {
    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    func snapshot() async -> Library {
        await store.current()
    }

    func follow(_ room: LiveRoom) async {
        await store.follow(
            FollowedAnchor(roomID: room.id, anchorName: room.anchorName, avatarURL: room.avatarURL, followedAt: .now))
    }

    func unfollow(roomID: RoomID) async {
        await store.unfollow(roomID: roomID)
    }

    func markWatched(roomID: RoomID) async {
        await store.markWatched(roomID: roomID, at: .now)
    }
}
