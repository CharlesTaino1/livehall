import AppKit
import Observation

@MainActor
@Observable
final class PreviewModel {
    struct Hover: Equatable {
        let cardID: String
        let roomID: RoomID
    }

    private(set) var expandedCardID: String?
    private(set) var isShowingVideo = false
    private(set) var videoLayer: CALayer?
    private(set) var isBillboardActive = false

    @ObservationIgnored private let repository: LiveRepository
    @ObservationIgnored private var hover: Hover?
    @ObservationIgnored private var pending: Hover?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var billboardRoomID: RoomID?
    @ObservationIgnored private var isPlayerOpen = false
    @ObservationIgnored private var isWindowVisible = true
    @ObservationIgnored private var player: LivePlayer?
    @ObservationIgnored private var playingSlot: Slot?
    @ObservationIgnored private var stateTask: Task<Void, Never>?

    private struct Slot: Equatable {
        let roomID: RoomID
        let tier: StreamTier
    }

    init(repository: LiveRepository) {
        self.repository = repository
    }

    func pointerEntered(_ target: Hover) {
        hoverTask?.cancel()
        pending = target
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Motion.hoverDelay)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.hover = target
            self.reconcile()
        }
    }

    func pointerExited(_ target: Hover) {
        if pending == target {
            hoverTask?.cancel()
            pending = nil
        }
        if hover == target {
            hover = nil
            reconcile()
        }
    }

    func setBillboard(roomID: RoomID?) {
        billboardRoomID = roomID
        reconcile()
    }

    func setPlayerOpen(_ isOpen: Bool) {
        isPlayerOpen = isOpen
        reconcile()
    }

    func setWindowVisible(_ isVisible: Bool) {
        isWindowVisible = isVisible
        reconcile()
    }

    private func reconcile() {
        let suspended = isPlayerOpen || !isWindowVisible
        let wanted: Slot?
        if suspended {
            wanted = nil
        } else if let hover {
            wanted = Slot(roomID: hover.roomID, tier: .economy)
        } else if let billboardRoomID {
            wanted = Slot(roomID: billboardRoomID, tier: .high)
        } else {
            wanted = nil
        }
        let expanded = suspended ? nil : hover?.cardID
        if expandedCardID != expanded { expandedCardID = expanded }
        let billboardActive = !suspended && hover == nil && billboardRoomID != nil
        if isBillboardActive != billboardActive { isBillboardActive = billboardActive }
        guard wanted != playingSlot else { return }
        tearDown()
        guard let wanted else { return }
        start(wanted)
    }

    private func start(_ slot: Slot) {
        let player = LivePlayer()
        player.isMuted = true
        player.displayLayer.videoGravity = .resizeAspectFill
        player.play(locator: repository.previewLocator(roomID: slot.roomID, tier: slot.tier))
        self.player = player
        playingSlot = slot
        videoLayer = player.displayLayer
        stateTask = Task { [weak self, states = player.states] in
            for await state in states {
                guard let self, !Task.isCancelled else { return }
                self.isShowingVideo = state == .playing
            }
        }
    }

    private func tearDown() {
        stateTask?.cancel()
        stateTask = nil
        player?.stop()
        player = nil
        playingSlot = nil
        videoLayer = nil
        isShowingVideo = false
    }
}
