import AppKit
import QuartzCore

final class DanmakuLayerView: NSView {
    private final class Item {
        let layer: CALayer
        let width: CGFloat
        let startTime: CFTimeInterval
        let startX: CGFloat
        let speed: CGFloat
        var isFinished = false

        init(layer: CALayer, width: CGFloat, startTime: CFTimeInterval, startX: CGFloat, speed: CGFloat) {
            self.layer = layer
            self.width = width
            self.startTime = startTime
            self.startX = startX
            self.speed = speed
        }

        func x(at time: CFTimeInterval) -> CGFloat {
            startX - speed * (time - startTime)
        }

        func isGone(at time: CFTimeInterval) -> Bool { x(at: time) + width < 0 }
    }

    private static let maxPendingAge: CFTimeInterval = 1

    private let rasterizer = DanmakuRasterizer()
    private var displayLink: CADisplayLink?
    private var active: [Item] = []
    private var freeLayers: [CALayer] = []
    private var waiting: [(item: RasterizedDanmaku, arrival: CFTimeInterval)] = []
    private var laneTails: [Item?] = []
    private var isEnabled = true
    private var settings = DanmakuSettings()
    private var inFlight = 0
    private var generation = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
        link.add(to: .main, forMode: .common)
        link.isPaused = active.isEmpty && waiting.isEmpty
        displayLink = link
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled { clear() }
    }

    func apply(_ newSettings: DanmakuSettings) {
        let old = settings
        guard newSettings != old else { return }
        settings = newSettings
        if newSettings.fontSize != old.fontSize || newSettings.typeface != old.typeface
            || newSettings.style != old.style || newSettings.area != old.area
        {
            clear()
        }
        if newSettings.opacity != old.opacity {
            for layer in active.map(\.layer) + freeLayers { layer.opacity = Float(newSettings.opacity) }
        }
    }

    func submit(_ messages: [DanmakuMessage]) {
        guard isEnabled else { return }
        let room = max(laneCount - waiting.count - inFlight, 0)
        let accepted = Array(messages.prefix(room))
        guard !accepted.isEmpty else { return }
        inFlight += accepted.count
        let scale = window?.backingScaleFactor ?? 2
        let look = DanmakuLook(settings)
        let submitted = generation
        Task {
            let items = await rasterizer.rasterize(accepted, look: look, scale: scale)
            inFlight -= accepted.count
            if submitted == generation { enqueue(items) }
        }
    }

    func clear() {
        generation += 1
        for item in active {
            item.isFinished = true
            recycle(item.layer)
        }
        active.removeAll()
        waiting.removeAll()
        laneTails.removeAll()
        displayLink?.isPaused = true
    }

    private func enqueue(_ items: [RasterizedDanmaku]) {
        guard isEnabled else { return }
        let now = CACurrentMediaTime()
        waiting.append(contentsOf: items.map { ($0, now) })
        displayLink?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        spawn(now: now)

        active.removeAll { item in
            guard item.isGone(at: now) else { return false }
            item.isFinished = true
            recycle(item.layer)
            return true
        }

        if active.isEmpty && waiting.isEmpty { link.isPaused = true }
    }

    private var laneHeight: CGFloat { ceil(settings.fontSize.points * 1.25) + Theme.Danmaku.laneSpacing }

    private var laneCount: Int { max(Int(bounds.height * settings.area.fraction / laneHeight), 1) }

    private func spawn(now: CFTimeInterval) {
        guard !waiting.isEmpty else { return }
        let laneCount = laneCount
        if laneTails.count != laneCount {
            laneTails = (0..<laneCount).map { $0 < laneTails.count ? laneTails[$0] : nil }
        }
        let entryX = bounds.width

        var remaining: [(item: RasterizedDanmaku, arrival: CFTimeInterval)] = []
        for entry in waiting {
            guard now - entry.arrival <= Self.maxPendingAge else { continue }
            let speed = CGFloat(settings.speed)
            guard
                let lane = laneTails.firstIndex(where: {
                    guard let tail = $0, !tail.isFinished else { return true }
                    let tailEnd = tail.x(at: now) + tail.width
                    guard tailEnd + settings.density.gap <= entryX else { return false }
                    return speed <= tail.speed || entryX - speed * max(tailEnd, 0) / tail.speed >= 0
                })
            else {
                remaining.append(entry)
                continue
            }
            let width = entry.item.size.width
            let layer = dequeueLayer()
            layer.contents = entry.item.image
            layer.contentsScale = window?.backingScaleFactor ?? 2
            layer.bounds = CGRect(origin: .zero, size: entry.item.size)
            let top = Theme.Danmaku.topInset + CGFloat(lane) * laneHeight
            layer.position = CGPoint(x: -width, y: (bounds.height - top - entry.item.size.height).rounded())
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = entryX
            animation.toValue = -width
            animation.duration = Double((entryX + width) / speed)
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: "scroll")
            let item = Item(layer: layer, width: width, startTime: now, startX: entryX, speed: speed)
            active.append(item)
            laneTails[lane] = item
        }
        waiting = remaining
    }

    private func dequeueLayer() -> CALayer {
        if let layer = freeLayers.popLast() {
            layer.isHidden = false
            return layer
        }
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.opacity = Float(settings.opacity)
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "hidden": NSNull()]
        self.layer?.addSublayer(layer)
        return layer
    }

    private func recycle(_ layer: CALayer) {
        layer.removeAllAnimations()
        layer.isHidden = true
        layer.contents = nil
        freeLayers.append(layer)
    }
}
