import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ShortVideoViewModel {
    enum Phase {
        case loading
        case content
        case failed(offline: Bool)
    }

    struct Slot: Identifiable {
        let video: ShortVideo
        let offset: Int

        var id: String { video.id }
    }

    private static let staleAfter = Duration.seconds(3600)
    private static let prefetchDistance = 3

    private(set) var phase = Phase.loading
    private(set) var videos: [ShortVideo] = []
    private(set) var index = 0
    private(set) var isPaused = false
    private(set) var players: [String: ClipPlayer] = [:]
    private(set) var isAutoNext = false
    private(set) var comments: CommentsViewModel?
    private(set) var isCommentsOpen = false
    let settings: PlaybackSettings
    let danmaku: CommentDanmakuFeed

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let preferences: PreferencesRepository
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var isWindowVisible = true
    @ObservationIgnored private var isLoadingMore = false
    @ObservationIgnored private var playingID: String?
    @ObservationIgnored private var loadedAt: ContinuousClock.Instant?
    @ObservationIgnored private let logger = AppLogger(category: "ShortVideoViewModel")

    init(repository: LiveRepository, preferences: PreferencesRepository, network: NetworkMonitor) {
        self.repository = repository
        self.preferences = preferences
        self.network = network
        settings = PlaybackSettings(preferences: preferences)
        danmaku = CommentDanmakuFeed(settings: settings)
    }

    var current: ShortVideo? { videos.indices.contains(index) ? videos[index] : nil }

    var slots: [Slot] {
        (-1...1).compactMap { offset in
            let position = index + offset
            return videos.indices.contains(position) ? Slot(video: videos[position], offset: offset) : nil
        }
    }

    func activate() async {
        isActive = true
        let stored = await settings.load()
        guard isActive else { return }
        isAutoNext = stored.shortVideoAutoNext ?? false
        danmaku.isEnabled = stored.shortVideoDanmaku ?? true
        danmaku.start()
        if videos.isEmpty || isStale {
            await load()
        } else {
            reconcile()
        }
    }

    func deactivate() {
        isActive = false
        comments = nil
        isCommentsOpen = false
        danmaku.stop()
        releasePlayers()
        settings.flush()
    }

    func setWindowVisible(_ visible: Bool) {
        isWindowVisible = visible
        applyPlayback()
    }

    func load() async {
        phase = .loading
        releasePlayers()
        do throws(LiveError) {
            let fresh = try await repository.shortVideos()
            guard !Task.isCancelled else { return }
            show(fresh)
        } catch {
            logger.error("短视频加载失败：\(String(describing: error))")
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
            let fresh = try await repository.shortVideos()
            guard !Task.isCancelled, !fresh.isEmpty else { return }
            releasePlayers()
            show(fresh)
        } catch {
            logger.error("短视频刷新失败：\(String(describing: error))")
        }
    }

    func retryWhenOnline() async {
        for await isOnline in network.updates() where isOnline {
            if case .failed = phase { await load() }
        }
    }

    func next() {
        if index + 1 < videos.count {
            index += 1
            isPaused = false
            reconcile()
        }
        loadMoreIfNeeded()
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
        isPaused = false
        reconcile()
    }

    func togglePause() {
        isPaused.toggle()
        applyPlayback()
    }

    func toggleMute() {
        settings.isMuted.toggle()
        applyAudio()
    }

    func setVolume(_ volume: Double) {
        settings.volume = volume
        if volume > 0 { settings.isMuted = false }
        applyAudio()
    }

    func toggleAutoNext() {
        isAutoNext.toggle()
        let value = isAutoNext
        Task { [preferences] in await preferences.update { $0.shortVideoAutoNext = value } }
        applyPlayback()
    }

    func seek(by seconds: Double) {
        if let current { players[current.id]?.seek(by: seconds) }
    }

    func toggleComments() {
        isCommentsOpen.toggle()
    }

    func toggleDanmaku() {
        danmaku.isEnabled.toggle()
        let value = danmaku.isEnabled
        Task { [preferences] in await preferences.update { $0.shortVideoDanmaku = value } }
    }

    func closeCommentsIfOpen() -> Bool {
        guard isCommentsOpen else { return false }
        isCommentsOpen = false
        return true
    }

    private var isStale: Bool {
        loadedAt.map { ContinuousClock.now - $0 > Self.staleAfter } ?? true
    }

    private func followComments() {
        guard comments?.video.id != current?.id else { return }
        guard let current else {
            comments = nil
            danmaku.follow(nil)
            return
        }
        let fresh = CommentsViewModel(video: current, repository: repository)
        comments = fresh
        danmaku.follow(fresh)
        Task { await fresh.load() }
    }

    private func show(_ fresh: [ShortVideo]) {
        videos = fresh
        index = 0
        isPaused = false
        loadedAt = .now
        phase = fresh.isEmpty ? .failed(offline: false) : .content
        reconcile()
    }

    private func loadMoreIfNeeded() {
        guard !isLoadingMore, index >= videos.count - Self.prefetchDistance else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do throws(LiveError) {
                let more = try await repository.shortVideos()
                let known = Set(videos.map(\.id))
                videos += more.filter { !known.contains($0.id) }
                reconcile()
            } catch {
                logger.error("短视频续取失败：\(String(describing: error))")
            }
        }
    }

    private func reconcile() {
        guard isActive else { return }
        let wanted = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0.video) })
        for (id, player) in players where wanted[id] == nil {
            player.stop()
            players[id] = nil
        }
        for (id, video) in wanted where players[id] == nil {
            players[id] = ClipPlayer(
                url: video.playURL, userAgent: DouyinAPI.userAgent, headers: DouyinAPI.videoHeaders)
        }
        if let previousID = playingID, previousID != current?.id { players[previousID]?.rewind() }
        playingID = current?.id
        followComments()
        applyAudio()
        applyPlayback()
    }

    private func applyPlayback() {
        danmaku.isPlaying = isActive && isWindowVisible && !isPaused
        for slot in slots {
            guard let player = players[slot.id] else { continue }
            if slot.offset == 0, isAutoNext {
                player.onPlayedToEnd = { [weak self] in self?.advanceAfterEnd() }
            } else {
                player.onPlayedToEnd = nil
            }
            if slot.offset == 0, isActive, isWindowVisible, !isPaused {
                player.play()
            } else {
                player.pause()
            }
        }
    }

    private func advanceAfterEnd() {
        guard index + 1 < videos.count else {
            if let current { players[current.id]?.rewind() }
            applyPlayback()
            loadMoreIfNeeded()
            return
        }
        withAnimation(Theme.Motion.layout) { next() }
    }

    private func applyAudio() {
        for player in players.values {
            player.setAudio(volume: Float(settings.volume), isMuted: settings.isMuted)
        }
    }

    private func releasePlayers() {
        for player in players.values { player.stop() }
        players = [:]
        playingID = nil
    }
}
