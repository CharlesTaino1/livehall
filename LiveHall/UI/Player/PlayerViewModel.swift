import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private(set) var isFollowing = false
    private(set) var ranking: RoomRanking?

    var volume: Double {
        get { settings.volume }
        set {
            settings.volume = newValue
            session.volume = Float(newValue)
        }
    }
    var isMuted: Bool {
        get { settings.isMuted }
        set {
            settings.isMuted = newValue
            session.isMuted = newValue
        }
    }
    var isDanmakuEnabled: Bool {
        get { session.isDanmakuEnabled }
        set { session.isDanmakuEnabled = newValue }
    }
    var danmakuSettings: DanmakuSettings {
        get { settings.danmaku }
        set {
            settings.danmaku = newValue
            session.danmakuSettings = newValue
        }
    }

    let session: RoomSession
    let controls = ControlsVisibility()

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let preferences: PreferencesRepository
    @ObservationIgnored private let settings: PlaybackSettings
    @ObservationIgnored private var roomID: RoomID?
    @ObservationIgnored private var rankingTask: Task<Void, Never>?
    @ObservationIgnored private let logger = AppLogger(category: "PlayerViewModel")
    @ObservationIgnored private var hasAppliedPreferences = false

    init(repository: LiveRepository, library: LibraryRepository, preferences: PreferencesRepository) {
        self.repository = repository
        self.library = library
        self.preferences = preferences
        settings = PlaybackSettings(preferences: preferences)
        session = RoomSession(repository: repository)
        session.onRoomLoaded = { [weak self] room in
            self?.recordVisit(of: room)
            self?.loadRanking(of: room)
        }
    }

    func open(roomID: RoomID) {
        guard session.screen == .idle else { return }
        self.roomID = roomID
        retry()
    }

    func retry() {
        guard let roomID else { return }
        session.open(roomID: roomID) { [weak self] in await self?.applyStoredPreferences() }
    }

    func close() {
        rankingTask?.cancel()
        session.close()
        controls.stop()
        settings.flush()
    }

    func selectQuality(rate: Int) {
        guard rate != session.streamPreference.rate else { return }
        session.streamPreference.rate = rate
        switchStream()
    }

    func selectLine(cdn: String) {
        guard cdn != session.streamPreference.cdn else { return }
        session.streamPreference.cdn = cdn
        switchStream()
    }

    func toggleFollow() {
        guard let room = session.room else { return }
        isFollowing.toggle()
        let following = isFollowing
        Task {
            if following {
                await library.follow(room)
            } else {
                await library.unfollow(roomID: room.id)
            }
        }
    }

    private func applyStoredPreferences() async {
        guard !hasAppliedPreferences else { return }
        let stored = await settings.load()
        guard !Task.isCancelled else { return }
        hasAppliedPreferences = true
        session.danmakuSettings = stored.danmaku
        if let platform = roomID?.platform { session.streamPreference = stored.streamPreference(for: platform) }
        session.volume = Float(stored.volume)
        session.isMuted = stored.isMuted
    }

    private func switchStream() {
        let stream = session.streamPreference
        guard let platform = roomID?.platform else { return }
        Task { [preferences] in await preferences.update { $0.setStreamPreference(stream, for: platform) } }
        session.switchStream()
    }

    private func recordVisit(of room: LiveRoom) {
        Task {
            await library.markWatched(roomID: room.id)
            let following = await library.snapshot().isFollowing(room.id)
            guard session.room?.id == room.id else { return }
            isFollowing = following
        }
    }

    private func loadRanking(of room: LiveRoom) {
        rankingTask?.cancel()
        ranking = nil
        guard room.isLive else { return }
        rankingTask = Task {
            do {
                let ranking = try await repository.ranking(roomID: room.id)
                guard !Task.isCancelled else { return }
                self.ranking = ranking
            } catch {
                logger.error("取榜单名次失败：\(String(describing: error))")
            }
        }
    }
}
