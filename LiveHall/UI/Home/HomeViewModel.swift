import Foundation
import Observation
import os

@MainActor
@Observable
final class HomeViewModel {
    enum Problem {
        case offline
        case failed
        case empty

        var symbol: String {
            switch self {
            case .offline: "wifi.slash"
            case .failed: "exclamationmark.triangle"
            case .empty: "tv.slash"
            }
        }

        var message: String {
            switch self {
            case .offline: "网络不可用，请检查连接"
            case .failed: "加载失败，请重试"
            case .empty: "暂时没有直播"
            }
        }
    }

    enum Phase {
        case loading
        case content
        case failed(Problem)
    }

    struct CategoryRow: Identifiable {
        let category: LiveCategory
        var state: LoadState<[RoomSummary]>

        var id: String { category.id }

        var isVisible: Bool {
            if case .loaded(let rooms) = state { !rooms.isEmpty } else { true }
        }
    }

    private(set) var phase = Phase.loading
    private(set) var billboard: RoomSummary?
    private(set) var followingLive: [RoomSummary] = []
    private(set) var recents: [RoomSummary] = []
    private(set) var categoryRows: [CategoryRow] = []
    private(set) var categoriesFailed = false

    var isOffline: Bool { isNetworkDown || lastRequestUnreachable }

    private static let categoryRowCount = 6
    private static let recentRowLimit = 20
    private static let categoryConcurrency = 2
    private static let cachedRoomsPerRow = 30

    private var isNetworkDown = false
    private var lastRequestUnreachable = false

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    @ObservationIgnored private let logger = AppLogger(category: "HomeViewModel")
    @ObservationIgnored private let signposter = OSSignposter(
        subsystem: "com.charlesshome.livehall", category: "HomeViewModel")

    init(repository: LiveRepository, library: LibraryRepository, network: NetworkMonitor) {
        self.repository = repository
        self.library = library
        self.network = network
    }

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        networkTask = Task { await watchNetwork() }
        reload()
    }

    func reload() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    func refresh() async {
        loadTask?.cancel()
        let task = Task { await load() }
        loadTask = task
        await task.value
    }

    func retryCategories() {
        Task { await loadCategoryRows() }
    }

    func retry(category: LiveCategory) {
        Task { await loadRow(category) }
    }

    func refreshLibraryRows() {
        Task { await loadLibraryRows() }
    }

    private var needsReload: Bool {
        if case .failed = phase { return true }
        if categoriesFailed { return true }
        return categoryRows.contains { if case .failed = $0.state { true } else { false } }
    }

    private func watchNetwork() async {
        for await isOnline in network.updates() {
            let wasDown = isNetworkDown
            isNetworkDown = !isOnline
            guard isOnline else { continue }
            lastRequestUnreachable = false
            if wasDown || needsReload { reload() }
        }
    }

    private func load() async {
        let interval = signposter.beginInterval("HomeLoad")
        defer { signposter.endInterval("HomeLoad", interval) }
        if billboard == nil {
            if let cached = await repository.cachedHome() {
                guard !Task.isCancelled else { return }
                apply(cached)
            } else {
                phase = .loading
            }
        }
        let libraryTask = Task { await loadLibraryRows() }
        do throws(LiveError) {
            let recommended = try await repository.recommendations()
            guard !Task.isCancelled else { return }
            guard let first = recommended.first else {
                if billboard == nil { phase = .failed(.empty) }
                return
            }
            billboard = first
            phase = .content
            lastRequestUnreachable = false
        } catch {
            guard !Task.isCancelled else { return }
            noteFailure(error)
            if billboard == nil { phase = .failed(error == .networkDown ? .offline : .failed) }
            await libraryTask.value
            return
        }
        await loadCategoryRows()
        await libraryTask.value
        await saveSnapshot()
    }

    private func loadCategoryRows() async {
        let categories: [LiveCategory]
        do throws(LiveError) {
            categories = Array(try await repository.categories().prefix(Self.categoryRowCount))
        } catch {
            logger.error("分区列表加载失败：\(String(describing: error))")
            noteFailure(error)
            categoriesFailed = categoryRows.isEmpty
            return
        }
        guard !Task.isCancelled else { return }
        categoriesFailed = false
        let existing = Dictionary(uniqueKeysWithValues: categoryRows.map { ($0.id, $0.state) })
        categoryRows = categories.map { CategoryRow(category: $0, state: existing[$0.id] ?? .loading) }
        await withTaskGroup(of: Void.self) { group in
            var pending = categories.makeIterator()
            func addNext() {
                guard let category = pending.next() else { return }
                group.addTask { await self.loadRow(category) }
            }
            for _ in 0..<Self.categoryConcurrency { addNext() }
            while await group.next() != nil { addNext() }
        }
    }

    private func loadRow(_ category: LiveCategory) async {
        do throws(LiveError) {
            let rooms = try await repository.rooms(category: category).rooms
            guard !Task.isCancelled else { return }
            setState(.loaded(rooms), for: category.id)
        } catch {
            guard !Task.isCancelled else { return }
            noteFailure(error)
            if case .loaded = categoryRows.first(where: { $0.id == category.id })?.state { return }
            setState(.failed, for: category.id)
        }
    }

    private func setState(_ state: LoadState<[RoomSummary]>, for id: String) {
        guard let index = categoryRows.firstIndex(where: { $0.id == id }) else { return }
        categoryRows[index].state = state
    }

    private func loadLibraryRows() async {
        let snapshot = await library.snapshot()
        let recentIDs = snapshot.recents.prefix(Self.recentRowLimit).map(\.roomID)
        let ids = Array(Set(snapshot.follows.map(\.roomID) + recentIDs))
        guard !ids.isEmpty else {
            followingLive = []
            recents = []
            return
        }
        do throws(LiveError) {
            let summaries = try await repository.summaries(roomIDs: ids)
            let found = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
            guard !Task.isCancelled else { return }
            followingLive = snapshot.follows.compactMap { found[$0.roomID] }
                .filter(\.isLive)
                .sorted { $0.popularity > $1.popularity }
            recents = recentIDs.compactMap { found[$0] }
        } catch {
            logger.error("关注与最近看过加载失败：\(String(describing: error))")
            noteFailure(error)
        }
    }

    private func noteFailure(_ error: LiveError) {
        if error == .networkDown { lastRequestUnreachable = true }
    }

    private func apply(_ snapshot: HomeSnapshot) {
        billboard = snapshot.billboard
        followingLive = snapshot.followingLive
        recents = snapshot.recents
        categoryRows = snapshot.categoryRows.map { CategoryRow(category: $0.category, state: .loaded($0.rooms)) }
        phase = snapshot.billboard == nil ? .loading : .content
    }

    private func saveSnapshot() async {
        let rows = categoryRows.compactMap { row -> HomeSnapshot.CategoryRoomList? in
            guard case .loaded(let rooms) = row.state else { return nil }
            return HomeSnapshot.CategoryRoomList(
                category: row.category, rooms: Array(rooms.prefix(Self.cachedRoomsPerRow)))
        }
        await repository.saveHome(
            HomeSnapshot(
                savedAt: .now, billboard: billboard, followingLive: followingLive, recents: recents,
                categoryRows: rows))
    }
}
