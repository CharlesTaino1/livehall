import Foundation
import Observation
import QuartzCore
import os

@MainActor
@Observable
final class RoomSession {
    enum Notice: Equatable {
        case roomNotFound
        case notLive
        case networkDown
        case ended
        case unsupported
        case failed

        var isRetryable: Bool {
            switch self {
            case .networkDown, .failed: true
            case .roomNotFound, .notLive, .ended, .unsupported: false
            }
        }

        var message: String {
            switch self {
            case .roomNotFound: "房间不存在"
            case .notLive: "主播未开播"
            case .networkDown: "网络不可用，请检查连接"
            case .ended: "主播已下播"
            case .unsupported: "暂不支持这路直播的编码"
            case .failed: "加载失败，请重试"
            }
        }
    }

    enum Screen: Equatable {
        case idle
        case loading
        case playing
        case notice(Notice)
    }

    private static let duplicateWindow = Duration.seconds(4)

    private(set) var room: LiveRoom?
    private(set) var audienceCount: Int?
    private(set) var screen: Screen = .idle
    private(set) var interruption: String?
    private(set) var qualities: [StreamQuality] = []
    private(set) var lines: [StreamLine] = []
    private(set) var currentRate: Int?
    private(set) var currentCDN: String?
    var streamPreference = StreamPreference()

    var isDanmakuEnabled = true {
        didSet {
            if !isDanmakuEnabled { danmakuChannel.clear() }
        }
    }
    var danmakuSettings = DanmakuSettings()
    var receivesDanmaku = true {
        didSet { if receivesDanmaku != oldValue { reconcileDanmaku() } }
    }

    let danmakuChannel = DanmakuChannel()
    var videoLayer: CALayer { player.displayLayer }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    @ObservationIgnored var onRoomLoaded: ((LiveRoom) -> Void)?

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let player = LivePlayer()
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var danmakuTask: Task<Void, Never>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var streamGeneration = 0
    @ObservationIgnored private var isSwitching = false
    @ObservationIgnored private var recentTexts: [String: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var isVideoActive = true
    @ObservationIgnored private var openedAt = ContinuousClock.now
    @ObservationIgnored private var openInterval: OSSignpostIntervalState?

    @ObservationIgnored private let signposter = OSSignposter(
        subsystem: "com.charlesshome.livehall", category: "RoomSession")
    @ObservationIgnored private let logger = AppLogger(category: "RoomSession")

    init(repository: LiveRepository) {
        self.repository = repository
        stateTask = Task { [weak self, states = player.states] in
            for await state in states { self?.apply(state) }
        }
    }

    func open(roomID: RoomID, prepare: @escaping @MainActor () async -> Void = {}) {
        openTask?.cancel()
        openTask = Task { await load(roomID: roomID, prepare: prepare) }
    }

    func close() {
        openTask?.cancel()
        stop()
        stateTask?.cancel()
    }

    func switchStream() {
        guard let room else { return }
        isSwitching = true
        interruption = "正在切换"
        player.switchStream(locator: locator(roomID: room.id))
    }

    func setVideoActive(_ active: Bool) {
        guard active != isVideoActive else { return }
        isVideoActive = active
        player.setVideoActive(active)
        if !active { danmakuChannel.clear() }
    }

    private func load(roomID: RoomID, prepare: @MainActor () async -> Void) async {
        stop()
        openedAt = .now
        openInterval = signposter.beginInterval("OpenToFirstFrame")
        screen = .loading
        room = nil
        audienceCount = nil
        qualities = []
        lines = []
        currentRate = nil
        currentCDN = nil
        await prepare()
        guard !Task.isCancelled else { return }
        do throws(LiveError) {
            let room = try await repository.room(id: roomID)
            guard !Task.isCancelled else { return }
            self.room = room
            onRoomLoaded?(room)
            guard room.isLive else {
                finishOpenInterval("not-live")
                screen = .notice(.notLive)
                return
            }
            player.play(locator: locator(roomID: room.id))
            reconcileDanmaku()
        } catch {
            finishOpenInterval("error")
            screen = .notice(Self.notice(for: error))
        }
    }

    private func reconcileDanmaku() {
        danmakuTask?.cancel()
        danmakuTask = nil
        guard receivesDanmaku, let room, room.isLive else { return }
        danmakuTask = Task { [weak self, stream = repository.events(room: room)] in
            for await event in stream {
                guard let self else { continue }
                switch event {
                case .audienceCount(let count):
                    self.audienceCount = count
                case .danmaku(let batch):
                    guard self.isDanmakuEnabled, self.isVideoActive else { continue }
                    let settings = self.danmakuSettings
                    let shown = self.removeRecentDuplicates(batch.filter { !settings.isBlocked($0.text) })
                    if !shown.isEmpty { self.danmakuChannel.send(shown) }
                }
            }
        }
    }

    private func locator(roomID: RoomID) -> StreamLocator {
        streamGeneration += 1
        let generation = streamGeneration
        return repository.streamLocator(roomID: roomID, preference: streamPreference) { [weak self] stream in
            Task { @MainActor in self?.streamResolved(stream, generation: generation) }
        }
    }

    private func streamResolved(_ stream: LiveStream, generation: Int) {
        guard generation == streamGeneration else { return }
        qualities = stream.qualities
        lines = stream.lines
        currentRate = stream.currentRate
        currentCDN = stream.currentCDN
    }

    private func removeRecentDuplicates(_ batch: [DanmakuMessage]) -> [DanmakuMessage] {
        let now = ContinuousClock.now
        recentTexts = recentTexts.filter { $0.value + Self.duplicateWindow > now }
        return batch.filter { message in
            guard recentTexts[message.text] == nil else { return false }
            recentTexts[message.text] = now
            return true
        }
    }

    private func stop() {
        player.stop()
        danmakuTask?.cancel()
        danmakuTask = nil
        danmakuChannel.clear()
        recentTexts.removeAll()
        interruption = nil
        isSwitching = false
    }

    private func apply(_ state: PlaybackState) {
        switch state {
        case .idle:
            break
        case .connecting:
            if !isSwitching { interruption = nil }
        case .playing:
            isSwitching = false
            if screen != .playing {
                let elapsed = openedAt.duration(to: .now).components
                logger.info("打开到首帧 \(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000) ms")
                finishOpenInterval("playing")
            }
            screen = .playing
            interruption = nil
        case .buffering:
            interruption = "缓冲中"
        case .reconnecting(let networkDown):
            if isSwitching {
                isSwitching = false
            } else if screen == .playing {
                interruption = networkDown ? "网络已断开，正在重连" : "连接中断，正在重连"
            } else if networkDown {
                screen = .notice(.networkDown)
            }
        case .ended:
            interruption = nil
            screen = .notice(.ended)
        case .failed(let failure):
            interruption = nil
            screen = .notice(failure == .unsupportedCodec ? .unsupported : .failed)
        }
    }

    private func finishOpenInterval(_ label: StaticString) {
        guard let interval = openInterval else { return }
        signposter.endInterval("OpenToFirstFrame", interval, "\(label)")
        openInterval = nil
    }

    private static func notice(for error: LiveError) -> Notice {
        switch error {
        case .roomNotFound: .roomNotFound
        case .notLive: .notLive
        case .networkDown: .networkDown
        case .network, .badResponse, .signFailed: .failed
        }
    }
}
