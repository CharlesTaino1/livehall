import Foundation
import os

struct LiveRepository: Sendable {
    private let douyu: DouyuAPI
    private let douyin: DouyinAPI
    private let douyuDanmaku: DouyuDanmakuClient
    private let douyinDanmaku: DouyinDanmakuClient
    private let homeCache: HomeCache
    private let account: AccountRepository

    init(
        douyu: DouyuAPI, douyin: DouyinAPI, douyuDanmaku: DouyuDanmakuClient, douyinDanmaku: DouyinDanmakuClient,
        homeCache: HomeCache, account: AccountRepository
    ) {
        self.douyu = douyu
        self.douyin = douyin
        self.douyuDanmaku = douyuDanmaku
        self.douyinDanmaku = douyinDanmaku
        self.homeCache = homeCache
        self.account = account
    }

    func cachedHome() async -> HomeSnapshot? {
        await homeCache.load()
    }

    func saveHome(_ snapshot: HomeSnapshot) async {
        await homeCache.save(snapshot)
    }

    func room(id: RoomID) async throws(LiveError) -> LiveRoom {
        switch id.platform {
        case .douyu: try await douyu.room(id: id.number)
        case .douyin: try await douyin.room(webRid: id.number)
        }
    }

    func ranking(roomID: RoomID) async throws(LiveError) -> RoomRanking? {
        switch roomID.platform {
        case .douyu: try await douyu.ranking(roomID: roomID.number)
        case .douyin: nil
        }
    }

    func recommendations() async throws(LiveError) -> [RoomSummary] {
        let (douyu, douyin) = (douyu, douyin)
        return PlatformMerge.interleave(
            try await PlatformMerge.gather(count: 2) { index throws(LiveError) in
                index == 0 ? try await douyu.recommendations() : try await douyin.recommendations()
            })
    }

    func shortVideos() async throws(LiveError) -> [ShortVideo] {
        try await douyin.feed()
    }

    func comments(videoID: String, cursor: Int) async throws(LiveError) -> CommentPage {
        try await douyin.comments(videoID: videoID, cursor: cursor)
    }

    func categoryGroups() async throws(LiveError) -> [CategoryGroup] {
        let (douyu, douyin) = (douyu, douyin)
        return PlatformMerge.groups(
            try await PlatformMerge.gather(count: 2) { index throws(LiveError) in
                index == 0 ? try await douyu.categoryGroups() : try await douyin.categoryGroups()
            })
    }

    func categories() async throws(LiveError) -> [LiveCategory] {
        try await categoryGroups().flatMap(\.categories).enumerated()
            .sorted { ($0.element.liveCount ?? 0, $1.offset) > ($1.element.liveCount ?? 0, $0.offset) }
            .map(\.element)
    }

    func rooms(category: LiveCategory, page: Int = 1) async throws(LiveError) -> RoomPage {
        let repository = self
        let sources = category.sources
        let name = category.name
        let pages = try await PlatformMerge.gather(count: sources.count) { index throws(LiveError) in
            try await repository.rooms(source: sources[index], categoryName: name, page: page)
        }
        return RoomPage(
            rooms: PlatformMerge.interleave(pages.map(\.rooms)), pageCount: pages.map(\.pageCount).max() ?? page)
    }

    private func rooms(source: LiveCategory.Source, categoryName: String, page: Int) async throws(LiveError)
        -> RoomPage
    {
        switch source.platform {
        case .douyu: try await douyu.rooms(categoryID: source.id, page: page)
        case .douyin: try await douyin.rooms(source: source, categoryName: categoryName, page: page)
        }
    }

    func summaries(roomIDs: [RoomID]) async throws(LiveError) -> [RoomSummary] {
        var found: [RoomID: RoomSummary] = [:]
        var firstError: LiveError?
        let douyuIDs = roomIDs.filter { $0.platform == .douyu }.map(\.number)
        do throws(LiveError) {
            for summary in try await douyu.summaries(roomIDs: douyuIDs) { found[summary.id] = summary }
        } catch {
            firstError = error
        }
        let douyinIDs = roomIDs.filter { $0.platform == .douyin }.map(\.number)
        do throws(LiveError) {
            for summary in try await douyin.summaries(webRids: douyinIDs) { found[summary.id] = summary }
        } catch {
            firstError = firstError ?? error
        }
        if found.isEmpty, let firstError { throw firstError }
        return roomIDs.compactMap { found[$0] }
    }

    func streamLocator(
        roomID: RoomID, preference: StreamPreference, onResolved: @escaping @Sendable (LiveStream) -> Void
    ) -> StreamLocator {
        locator(roomID: roomID, rate: preference.rate, cdn: preference.cdn, onResolved: onResolved)
    }

    func previewLocator(roomID: RoomID, tier: StreamTier) -> StreamLocator {
        locator(roomID: roomID, rate: tier.rate(on: roomID.platform), cdn: "", onResolved: { _ in })
    }

    private func locator(
        roomID: RoomID, rate: Int, cdn: String, onResolved: @escaping @Sendable (LiveStream) -> Void
    ) -> StreamLocator {
        let failover = LineFailover()
        return { [douyu, douyin, account] failures async throws(StreamLocatingError) -> URLRequest in
            do throws(LiveError) {
                let line = failover.line(preferred: cdn, failures: failures)
                let stream: LiveStream
                switch roomID.platform {
                case .douyu:
                    stream = try await douyu.stream(
                        roomID: roomID.number, rate: rate, cdn: line, session: await account.session())
                case .douyin:
                    stream = try await douyin.stream(webRid: roomID.number, rate: rate, line: line)
                }
                failover.resolved(lines: stream.lines.map(\.cdn), current: stream.currentCDN)
                onResolved(stream)
                return stream.request
            } catch {
                switch error {
                case .notLive, .roomNotFound: throw .offline
                case .networkDown: throw .networkDown
                case .network, .badResponse, .signFailed: throw .failed
                }
            }
        }
    }

    func events(room: LiveRoom) -> AsyncStream<RoomEvent> {
        switch room.id.platform {
        case .douyu: douyuDanmaku.events(roomID: room.id.number)
        case .douyin: douyinDanmaku.events(roomID: room.connectionID)
        }
    }
}

private final class LineFailover: Sendable {
    private static let failuresPerSwitch = 2

    private struct State {
        var lines: [String] = []
        var current = ""
        var override: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func line(preferred: String, failures: Int) -> String {
        state.withLock { state in
            if failures > 0, failures % Self.failuresPerSwitch == 0, state.lines.count > 1 {
                let index = state.lines.firstIndex(of: state.current) ?? -1
                state.override = state.lines[(index + 1) % state.lines.count]
            }
            return state.override ?? preferred
        }
    }

    func resolved(lines: [String], current: String) {
        state.withLock {
            $0.lines = lines
            $0.current = current
        }
    }
}
