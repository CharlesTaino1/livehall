import AppKit

@MainActor
final class ScrollPager {
    private static let preciseThreshold: CGFloat = 50
    private static let wheelCooldown = Duration.milliseconds(400)

    var isEnabled = true

    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var hasTriggered = false
    private var lastWheelTrigger = ContinuousClock.now - .seconds(1)

    func start(_ handler: @escaping @MainActor (Int) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, handler) }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent, _ handler: @MainActor (Int) -> Void) {
        let delta = event.scrollingDeltaY
        guard isEnabled, delta != 0 else { return }
        let direction = delta < 0 ? 1 : -1
        guard event.hasPreciseScrollingDeltas else {
            guard ContinuousClock.now - lastWheelTrigger > Self.wheelCooldown else { return }
            lastWheelTrigger = .now
            handler(direction)
            return
        }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            accumulated = 0
            hasTriggered = false
        }
        guard !hasTriggered, event.momentumPhase.isEmpty else { return }
        accumulated += delta
        if abs(accumulated) >= Self.preciseThreshold {
            hasTriggered = true
            handler(accumulated < 0 ? 1 : -1)
        }
    }
}
