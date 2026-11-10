import AVFoundation
import Observation

@MainActor
@Observable
final class ClipPlayer {
    private(set) var isReadyForDisplay = false
    private(set) var isBuffering = false
    private(set) var hasFailed = false
    private(set) var progress = 0.0

    let layer = AVPlayerLayer()
    var onPlayedToEnd: (@MainActor () -> Void)?

    @ObservationIgnored private let player: AVPlayer
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var isWaiting = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    private static let logger = AppLogger(category: "ClipPlayer")

    init(url: URL, userAgent: String, headers: [String: String]) {
        let asset = AVURLAsset(
            url: url,
            options: [
                AVURLAssetHTTPUserAgentKey: userAgent,
                "AVURLAssetHTTPHeaderFieldsKey": headers,
            ])
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        layer.player = player
        layer.videoGravity = .resizeAspect

        observations = [
            layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                let isReady = layer.isReadyForDisplay
                Task { @MainActor in self?.isReadyForDisplay = isReady }
            },
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let isWaiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                Task { @MainActor in self?.setWaiting(isWaiting) }
            },
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard item.status == .failed else { return }
                let reason = item.error?.localizedDescription ?? ""
                Task { @MainActor in self?.fail(reason) }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.updateProgress(time) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.loop() }
        }
    }

    func play() {
        wantsPlay = true
        player.play()
        refreshBuffering()
    }

    func pause() {
        wantsPlay = false
        player.pause()
        refreshBuffering()
    }

    func rewind() {
        player.seek(to: .zero)
        progress = 0
    }

    func seek(by seconds: Double) {
        guard let item = player.currentItem, item.duration.isNumeric else { return }
        let target = min(max(player.currentTime().seconds + seconds, 0), max(item.duration.seconds - 0.5, 0))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func setAudio(volume: Float, isMuted: Bool) {
        player.volume = volume
        player.isMuted = isMuted
    }

    func stop() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        for observation in observations { observation.invalidate() }
        observations = []
        player.pause()
        player.replaceCurrentItem(with: nil)
        layer.player = nil
    }

    private func setWaiting(_ waiting: Bool) {
        isWaiting = waiting
        refreshBuffering()
    }

    private func refreshBuffering() {
        let value = wantsPlay && isWaiting
        if isBuffering != value { isBuffering = value }
    }

    private func fail(_ reason: String) {
        Self.logger.error("短视频播放失败：\(reason)")
        hasFailed = true
    }

    private func updateProgress(_ time: CMTime) {
        guard let duration = player.currentItem?.duration, duration.isNumeric, duration.seconds > 0 else { return }
        progress = min(max(time.seconds / duration.seconds, 0), 1)
    }

    private func loop() {
        if let onPlayedToEnd {
            onPlayedToEnd()
            return
        }
        player.seek(to: .zero)
        if wantsPlay { player.play() }
    }
}
