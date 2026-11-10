import Observation

@MainActor
@Observable
final class RoomPickerViewModel {
    struct Sections: Equatable {
        let following: [RoomSummary]
        let recents: [RoomSummary]
        let popular: [RoomSummary]
    }

    enum Phase {
        case loading
        case content(Sections)
        case failed(offline: Bool)
    }

    private static let recentLimit = 12

    private(set) var phase = Phase.loading

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let logger = AppLogger(category: "RoomPickerViewModel")

    init(repository: LiveRepository, library: LibraryRepository) {
        self.repository = repository
        self.library = library
    }

    func load() async {
        phase = .loading
        let snapshot = await library.snapshot()
        let followIDs = snapshot.follows.map(\.roomID)
        let recentIDs = snapshot.recents.prefix(Self.recentLimit).map(\.roomID)
        do throws(LiveError) {
            let known = Array(Set(followIDs + recentIDs))
            let found = known.isEmpty ? [] : try await repository.summaries(roomIDs: known)
            let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let popular = try await repository.recommendations()
            guard !Task.isCancelled else { return }
            phase = .content(
                Sections(
                    following: followIDs.compactMap { byID[$0] }.filter(\.isLive).sorted {
                        $0.popularity > $1.popularity
                    },
                    recents: recentIDs.compactMap { byID[$0] }.filter(\.isLive),
                    popular: popular.filter(\.isLive)))
        } catch {
            logger.error("选择面板加载失败：\(String(describing: error))")
            guard !Task.isCancelled else { return }
            phase = .failed(offline: error == .networkDown)
        }
    }
}
