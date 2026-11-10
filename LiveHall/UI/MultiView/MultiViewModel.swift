import Foundation
import Observation

@MainActor
@Observable
final class MultiViewModel {
    struct Cell: Identifiable {
        let session: RoomSession
        let roomID: RoomID
        let index: Int

        var id: RoomID { roomID }
    }

    private(set) var layout: MultiViewLayout
    private(set) var roomIDs: [RoomID]
    private(set) var focusedRoomID: RoomID?
    private(set) var maximizedRoomID: RoomID?
    private var sessions: [RoomID: RoomSession] = [:]

    let controls = ControlsVisibility()
    let settings: PlaybackSettings

    var isDanmakuEnabled = true {
        didSet {
            for session in sessions.values { session.isDanmakuEnabled = isDanmakuEnabled }
        }
    }

    var volume: Double {
        get { settings.volume }
        set {
            settings.volume = newValue
            applyAudio()
        }
    }

    var isMuted: Bool {
        get { settings.isMuted }
        set {
            settings.isMuted = newValue
            applyAudio()
        }
    }

    var danmakuSettings: DanmakuSettings {
        get { settings.danmaku }
        set {
            settings.danmaku = newValue
            for session in sessions.values { session.danmakuSettings = newValue }
        }
    }

    var cells: [Cell] {
        visibleRoomIDs.enumerated().compactMap { index, id in
            sessions[id].map { Cell(session: $0, roomID: id, index: index) }
        }
    }

    var visibleRoomIDs: [RoomID] { Array(roomIDs.prefix(layout.capacity)) }

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let preferences: PreferencesRepository
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var isWindowVisible = true
    @ObservationIgnored private var hasAppliedPreferences = false

    init(
        launch: MultiViewState, repository: LiveRepository, library: LibraryRepository,
        preferences: PreferencesRepository
    ) {
        layout = launch.layout
        roomIDs = Array(launch.roomIDs.prefix(MultiViewState.maxRooms))
        self.repository = repository
        self.library = library
        self.preferences = preferences
        settings = PlaybackSettings(preferences: preferences)
    }

    func activate() async {
        isActive = true
        controls.pointerMoved()
        if !hasAppliedPreferences {
            _ = await settings.load()
            hasAppliedPreferences = true
        }
        guard isActive else { return }
        if !visibleRoomIDs.contains(where: { $0 == focusedRoomID }) { focusedRoomID = visibleRoomIDs.first }
        syncSessions()
    }

    func deactivate() {
        isActive = false
        for session in sessions.values { session.close() }
        sessions.removeAll()
        maximizedRoomID = nil
        controls.stop()
        settings.flush()
    }

    func setWindowVisible(_ visible: Bool) {
        isWindowVisible = visible
        updateVideoActivity()
    }

    func add(roomID: RoomID) {
        if roomIDs.contains(roomID) {
            focus(roomID: roomID)
            return
        }
        if roomIDs.count < MultiViewState.maxRooms {
            roomIDs.append(roomID)
            if roomIDs.count > layout.capacity { layout = .quad }
        } else if let focused = focusedRoomID, let index = roomIDs.firstIndex(of: focused) {
            roomIDs[index] = roomID
        } else {
            roomIDs[roomIDs.count - 1] = roomID
        }
        focusedRoomID = roomID
        persist()
        syncSessions()
    }

    func remove(roomID: RoomID) {
        guard let index = roomIDs.firstIndex(of: roomID) else { return }
        roomIDs.remove(at: index)
        if maximizedRoomID == roomID { maximizedRoomID = nil }
        if focusedRoomID == roomID { focusedRoomID = visibleRoomIDs.first }
        persist()
        syncSessions()
    }

    func retry(roomID: RoomID) {
        sessions[roomID]?.open(roomID: roomID)
    }

    func setLayout(_ newLayout: MultiViewLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        maximizedRoomID = nil
        if let focused = focusedRoomID, !visibleRoomIDs.contains(focused) { focusedRoomID = visibleRoomIDs.first }
        persist()
        syncSessions()
    }

    func focus(roomID: RoomID) {
        guard visibleRoomIDs.contains(roomID), focusedRoomID != roomID else { return }
        focusedRoomID = roomID
        applyAudio()
    }

    func focus(index: Int) {
        guard visibleRoomIDs.indices.contains(index) else { return }
        focus(roomID: visibleRoomIDs[index])
    }

    func toggleMaximize(roomID: RoomID) {
        maximizedRoomID = maximizedRoomID == roomID ? nil : roomID
        focus(roomID: roomID)
        updateVideoActivity()
    }

    func restoreFromMaximized() -> Bool {
        guard maximizedRoomID != nil else { return false }
        maximizedRoomID = nil
        updateVideoActivity()
        return true
    }

    func makePicker() -> RoomPickerViewModel {
        RoomPickerViewModel(repository: repository, library: library)
    }

    private func syncSessions() {
        guard isActive else { return }
        let wanted = Set(visibleRoomIDs)
        for (id, session) in sessions where !wanted.contains(id) {
            session.close()
            sessions[id] = nil
        }
        for id in visibleRoomIDs {
            if let session = sessions[id] {
                let rate = layout.streamTier.rate(on: id.platform)
                if session.streamPreference.rate != rate {
                    session.streamPreference.rate = rate
                    session.switchStream()
                }
            } else {
                sessions[id] = makeSession(roomID: id)
            }
        }
        applyAudio()
        updateVideoActivity()
    }

    private func makeSession(roomID: RoomID) -> RoomSession {
        let session = RoomSession(repository: repository)
        session.streamPreference = StreamPreference(rate: layout.streamTier.rate(on: roomID.platform), cdn: "")
        session.danmakuSettings = settings.danmaku
        session.isDanmakuEnabled = isDanmakuEnabled
        session.onRoomLoaded = { [library] room in
            Task { await library.markWatched(roomID: room.id) }
        }
        session.open(roomID: roomID)
        return session
    }

    private func applyAudio() {
        for (id, session) in sessions {
            let hasSound = id == focusedRoomID
            session.volume = Float(settings.volume)
            session.isMuted = settings.isMuted || !hasSound
            session.receivesDanmaku = hasSound
        }
    }

    private func updateVideoActivity() {
        for (id, session) in sessions {
            session.setVideoActive(isWindowVisible && (maximizedRoomID == nil || maximizedRoomID == id))
        }
    }

    private func persist() {
        let state = MultiViewState(layout: layout, roomIDs: roomIDs)
        Task { [preferences] in await preferences.update { $0.multiView = state } }
    }
}
