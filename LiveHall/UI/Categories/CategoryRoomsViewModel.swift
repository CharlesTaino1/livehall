import Observation

@MainActor
@Observable
final class CategoryRoomsViewModel {
    enum Phase {
        case loading
        case content
        case empty
        case failed(offline: Bool)
    }

    let category: LiveCategory
    private(set) var phase = Phase.loading
    private(set) var rooms: [RoomSummary] = []
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false

    private static let prefetchDistance = 12

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var loadedPages = 0
    @ObservationIgnored private var pageCount = 1
    @ObservationIgnored private var knownIDs: Set<RoomID> = []
    @ObservationIgnored private let logger = AppLogger(category: "CategoryRoomsViewModel")

    init(category: LiveCategory, repository: LiveRepository, network: NetworkMonitor) {
        self.category = category
        self.repository = repository
        self.network = network
    }

    func load() async {
        phase = .loading
        rooms = []
        knownIDs = []
        loadedPages = 0
        do throws(LiveError) {
            let page = try await repository.rooms(category: category, page: 1)
            guard !Task.isCancelled else { return }
            pageCount = page.pageCount
            loadedPages = 1
            append(page.rooms)
            phase = rooms.isEmpty ? .empty : .content
        } catch {
            logger.error("分区直播间加载失败：\(String(describing: error))")
            guard !Task.isCancelled else { return }
            phase = .failed(offline: error == .networkDown)
        }
    }

    func refresh() async {
        guard case .content = phase else {
            await load()
            return
        }
        do throws(LiveError) {
            let page = try await repository.rooms(category: category, page: 1)
            guard !Task.isCancelled else { return }
            pageCount = page.pageCount
            loadedPages = 1
            loadMoreFailed = false
            rooms = []
            knownIDs = []
            append(page.rooms)
            phase = rooms.isEmpty ? .empty : .content
        } catch {
            logger.error("分区直播间刷新失败：\(String(describing: error))")
        }
    }

    func roomAppeared(_ room: RoomSummary) {
        guard case .content = phase, !isLoadingMore, !loadMoreFailed, loadedPages < pageCount,
            let index = rooms.firstIndex(where: { $0.id == room.id }),
            index >= rooms.count - Self.prefetchDistance
        else { return }
        Task { await loadMore() }
    }

    func retryLoadMore() {
        loadMoreFailed = false
        Task { await loadMore() }
    }

    func retryWhenOnline() async {
        for await isOnline in network.updates() where isOnline {
            if case .failed = phase {
                await load()
            } else if loadMoreFailed {
                loadMoreFailed = false
                await loadMore()
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do throws(LiveError) {
            let page = try await repository.rooms(category: category, page: loadedPages + 1)
            guard !Task.isCancelled else { return }
            pageCount = page.pageCount
            loadedPages += 1
            append(page.rooms)
        } catch {
            logger.error("分区翻页失败：\(String(describing: error))")
            loadMoreFailed = true
        }
    }

    private func append(_ newRooms: [RoomSummary]) {
        for room in newRooms where knownIDs.insert(room.id).inserted {
            rooms.append(room)
        }
    }
}
