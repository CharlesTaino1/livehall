import AVFoundation
import Foundation

@MainActor
final class LivePlayer {
    let displayLayer = AVSampleBufferDisplayLayer()
    let states: AsyncStream<PlaybackState>

    private let statesContinuation: AsyncStream<PlaybackState>.Continuation
    private let audioRenderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private var task: Task<Void, Never>?
    private var pipeline: PlaybackPipeline?
    private var isVideoActive = true
    private var displayWatch: Task<Void, Never>?
    private var isDetachedReported = false
    private static let logger = AppLogger(category: "LivePlayer")

    var volume: Float {
        get { audioRenderer.volume }
        set { audioRenderer.volume = newValue }
    }

    var isMuted: Bool {
        get { audioRenderer.isMuted }
        set { audioRenderer.isMuted = newValue }
    }

    init() {
        (states, statesContinuation) = AsyncStream.makeStream(of: PlaybackState.self)
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        audioRenderer.audioTimePitchAlgorithm = .timeDomain
        synchronizer.addRenderer(displayLayer.sampleBufferRenderer)
        synchronizer.addRenderer(audioRenderer)
    }

    func play(locator: @escaping StreamLocator) {
        let previous = task
        previous?.cancel()
        let pipeline = PlaybackPipeline(
            targets: RenderTargets(
                video: displayLayer.sampleBufferRenderer, audio: audioRenderer, synchronizer: synchronizer),
            states: statesContinuation)
        self.pipeline = pipeline
        watchDisplay()
        task = Task {
            await previous?.value
            if !self.isVideoActive { await pipeline.setVideoSuspended(true) }
            await pipeline.run(locator: locator)
        }
    }

    func switchStream(locator: @escaping StreamLocator) {
        guard let pipeline else { return }
        Task { await pipeline.replaceLocator(locator) }
    }

    func setVideoActive(_ active: Bool) {
        isVideoActive = active
        guard let pipeline else { return }
        Task { await pipeline.setVideoSuspended(!self.isVideoActive) }
    }

    func stop() {
        task?.cancel()
        displayWatch?.cancel()
        displayWatch = nil
    }

    private func watchDisplay() {
        displayWatch?.cancel()
        displayWatch = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                self?.checkDisplay()
            }
        }
    }

    private func checkDisplay() {
        let isDetached = isVideoActive && displayLayer.superlayer == nil
        guard isDetached != isDetachedReported else { return }
        isDetachedReported = isDetached
        if isDetached {
            Self.logger.warning("窗口可见但画面图层没挂进窗口，只有声音")
        } else {
            Self.logger.info("画面图层已挂回窗口")
        }
    }
}
