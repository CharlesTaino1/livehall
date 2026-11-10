import Observation

@MainActor
@Observable
final class FollowsViewModel {
    enum Phase {
        case loading
        case empty
        case content([RoomSummary])
        case failed(offline: Bool)
    }

    private(set) var phase = Phase.loading

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private let logger = AppLogger(category: "FollowsViewModel")

    init(repository: LiveRepository, library: LibraryRepository, network: NetworkMonitor) {
        self.repository = repository
        self.library = library
        self.network = network
    }

    func retryWhenOnline() async {
        for await isOnline in network.updates() where isOnline {
            if case .failed = phase { await load() }
        }
    }

    func load() async {
        let snapshot = await library.snapshot()
        guard !snapshot.follows.isEmpty else {
            phase = .empty
            return
        }
        do throws(LiveError) {
            let found = Dictionary(
                uniqueKeysWithValues: try await repository.summaries(roomIDs: snapshot.follows.map(\.roomID))
                    .map { ($0.id, $0) })
            guard !Task.isCancelled else { return }
            let rooms = snapshot.follows.map { found[$0.roomID] ?? Self.offlineRoom($0) }
            let live = rooms.filter(\.isLive).sorted { $0.popularity > $1.popularity }
            phase = .content(live + rooms.filter { !$0.isLive })
        } catch {
            logger.error("关注列表加载失败：\(String(describing: error))")
            guard !Task.isCancelled else { return }
            if case .content = phase { return }
            phase = .failed(offline: error == .networkDown)
        }
    }

    private static func offlineRoom(_ anchor: FollowedAnchor) -> RoomSummary {
        RoomSummary(
            id: anchor.roomID, anchorName: anchor.anchorName, title: "", categoryName: "", popularity: 0,
            coverURL: nil, avatarURL: anchor.avatarURL, isLive: false)
    }
}
