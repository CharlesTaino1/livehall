import Observation

@MainActor
@Observable
final class ControlsVisibility {
    private(set) var isVisible = true
    private(set) var isPointerInside = true

    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var lastActivity = ContinuousClock.now
    @ObservationIgnored private var isPinned = false

    init() {
        ensureHideLoop()
    }

    func pointerMoved() {
        isPointerInside = true
        lastActivity = .now
        if !isVisible { isVisible = true }
        ensureHideLoop()
    }

    func pointerLeft() {
        isPointerInside = false
        guard !isPinned else { return }
        hideTask?.cancel()
        hideTask = nil
        isVisible = false
    }

    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            isVisible = true
        } else {
            pointerMoved()
        }
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func ensureHideLoop() {
        guard hideTask == nil else { return }
        hideTask = Task { [weak self] in
            while let self {
                let deadline = self.lastActivity + Theme.Motion.controlsIdleDelay
                if ContinuousClock.now >= deadline {
                    if !self.isPinned { self.isVisible = false }
                    self.hideTask = nil
                    return
                }
                do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            }
        }
    }
}
