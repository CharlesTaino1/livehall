import Observation

@MainActor
@Observable
final class PlaybackSettings {
    var volume = 1.0 {
        didSet { if volume != oldValue { scheduleSave() } }
    }
    var isMuted = false {
        didSet { if isMuted != oldValue { scheduleSave() } }
    }
    var danmaku = DanmakuSettings() {
        didSet { if danmaku != oldValue { scheduleSave() } }
    }

    @ObservationIgnored private let preferences: PreferencesRepository
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(preferences: PreferencesRepository) {
        self.preferences = preferences
    }

    func load() async -> Preferences {
        let stored = await preferences.current()
        guard !hasLoaded, !Task.isCancelled else { return stored }
        hasLoaded = true
        volume = stored.volume
        isMuted = stored.isMuted
        danmaku = stored.danmaku
        return stored
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasLoaded else { return }
        let (volume, isMuted, danmaku) = (volume, isMuted, danmaku)
        Task { [preferences] in
            await preferences.update {
                $0.volume = volume
                $0.isMuted = isMuted
                $0.danmaku = danmaku
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.flush()
        }
    }
}
