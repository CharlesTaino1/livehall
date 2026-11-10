import AVFoundation
import CoreMedia
import Foundation
import os

struct RenderTargets: @unchecked Sendable {
    let video: AVSampleBufferVideoRenderer
    let audio: AVSampleBufferAudioRenderer
    let synchronizer: AVSampleBufferRenderSynchronizer
}

private enum PipelineError: Error {
    case unsupportedCodec
    case rendererFailed
}

actor PlaybackPipeline {
    private enum Tuning {
        static let underrun = 0.04
        static let reserveLevels: [Double] = [1.5, 2.5, 3.5]
        static let reserveDecay: Duration = .seconds(60)
        static let startupHoldLimit: Duration = .milliseconds(2500)
        static let refillHoldLimit: Duration = .seconds(6)
        static let catchUpHigh = 1.0
        static let catchUpLow = 0.3
        static let catchUpRate: Float = 1.05
        static let jumpMargin = 4.0
        static let minJump = CMTime(seconds: 0.5, preferredTimescale: 1000)
        static let keyframeHistory = 32
        static let silenceLimit: Duration = .seconds(2)
        static let stableConnection: Duration = .seconds(20)
        static let statsInterval: Duration = .seconds(10)
        static let startSettleWindow: Duration = .milliseconds(150)
        static let startSettleLimit: Duration = .milliseconds(400)
        static let burstGrowthRatio = 1.5
        static let tickInterval: Duration = .milliseconds(100)
        static let reconnectDelays: [Duration] = [.zero, .seconds(1), .seconds(2), .seconds(3), .seconds(5)]
        static let audioRealignMilliseconds = 100
    }

    private static let logger = AppLogger(category: "PlaybackPipeline")
    private static let nextID = OSAllocatedUnfairLock(initialState: 0)

    private let id = PlaybackPipeline.nextID.withLock { value -> Int in
        value += 1
        return value
    }

    private let queue = DispatchSerialQueue(label: "com.charlesshome.livehall.playback", qos: .userInteractive)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let targets: RenderTargets
    private let states: AsyncStream<PlaybackState>.Continuation
    private var state: PlaybackState = .idle

    private var demuxer = FLVDemuxer()
    private var videoFormat: VideoFormat?
    private var audioFormat: CMAudioFormatDescription?
    private var audioSampleRate = 0
    private var baseTime: Int?
    private var audioNextValue: Int64?
    private var pendingVideo = SampleQueue()
    private var pendingAudio = SampleQueue()
    private var lastVideoPTS = CMTime.zero
    private var recentKeyframes: [CMTime] = []
    private var hasStarted = false
    private var hold: (since: ContinuousClock.Instant, limit: Duration)?
    private var isVideoSuspended = false
    private var settleStart: ContinuousClock.Instant?
    private var settleWindowStart: ContinuousClock.Instant?
    private var settleWindowPTS = CMTime.zero
    private var reconnectAttempt = 0
    private var reserveLevel = 0
    private var reserveChangedAt = ContinuousClock.now
    private var stallCount = 0
    private var reconnectCount = 0
    private var statsAt = ContinuousClock.now
    private var statsCPUSeconds = ProcessUsage.current().cpuSeconds
    private var openedAt = ContinuousClock.now
    private var targetRate: Float = 1
    private var currentStream: ByteStream?
    private var rendererFailed = false
    private var connectedAt: ContinuousClock.Instant?
    private var failureStreak = 0
    private var lastChunkAt: ContinuousClock.Instant?
    private var isRequestingVideo = false
    private var isRequestingAudio = false
    private var locator: StreamLocator = { _ in throw .failed }
    private var locatorVersion = 0

    init(targets: RenderTargets, states: AsyncStream<PlaybackState>.Continuation) {
        self.targets = targets
        self.states = states
    }

    func run(locator initial: @escaping StreamLocator) async {
        locator = initial
        openedAt = .now
        resetConnection(removingImage: true)
        let monitor = Task { await self.monitor() }
        var networkDown = false

        loop: while !Task.isCancelled {
            update(reconnectAttempt == 0 ? .connecting : .reconnecting(networkDown: networkDown))
            do {
                let version = locatorVersion
                let locate = self.locator
                let request = try await locate(failureStreak)
                guard version == locatorVersion else { continue loop }
                let stream = ByteStream(request: request)
                currentStream = stream
                connectedAt = .now
                defer {
                    stream.cancel()
                    currentStream = nil
                }
                logInfo(
                    "连接建立 \(request.url?.lastPathComponent ?? "?")，用时 \(self.openedAt.duration(to: .now).milliseconds) ms"
                )
                for try await chunk in stream.chunks {
                    lastChunkAt = .now
                    try process(chunk)
                }
                networkDown = false
                if rendererFailed { throw PipelineError.rendererFailed }
            } catch is CancellationError {
                break loop
            } catch let error as StreamLocatingError {
                logWarning("取不到流：\(error)")
                switch error {
                case .offline:
                    update(.ended)
                    break loop
                case .networkDown: networkDown = true
                case .failed: networkDown = false
                }
            } catch PipelineError.unsupportedCodec {
                update(.failed(.unsupportedCodec))
                break loop
            } catch let error as ByteStreamError {
                if case .network(let code) = error {
                    networkDown = [.notConnectedToInternet, .dataNotAllowed, .cannotFindHost, .dnsLookupFailed]
                        .contains(code)
                } else {
                    networkDown = false
                }
                logError("字节流中断：\(String(describing: error))")
            } catch {
                networkDown = false
                logError("播放中断：\(String(describing: error))")
            }

            if let connectedAt, connectedAt.duration(to: .now) >= Tuning.stableConnection {
                failureStreak = 0
            } else {
                failureStreak += 1
            }
            connectedAt = nil
            resetConnection(removingImage: false)
            let delay = Tuning.reconnectDelays[min(reconnectAttempt, Tuning.reconnectDelays.count - 1)]
            reconnectAttempt += 1
            reconnectCount += 1
            update(.reconnecting(networkDown: networkDown))
            do { try await Task.sleep(for: delay) } catch { break loop }
        }

        monitor.cancel()
        deactivateRenderers()
        resetConnection(removingImage: Task.isCancelled)
        if Task.isCancelled { update(.idle) }
    }

    func replaceLocator(_ locator: @escaping StreamLocator) {
        logInfo("换流，断开当前连接重连")
        self.locator = locator
        locatorVersion += 1
        failureStreak = 0
        currentStream?.cancel()
    }

    private func process(_ chunk: Data) throws {
        let events: [FLVEvent]
        do {
            events = try demuxer.append(chunk)
        } catch .unsupportedVideoCodec {
            throw PipelineError.unsupportedCodec
        } catch .unsupportedAudioCodec {
            throw PipelineError.unsupportedCodec
        }
        for event in events {
            switch event {
            case .videoConfig(let codec, let config):
                do {
                    videoFormat = try SampleFactory.videoFormat(codec: codec, config: config)
                } catch {
                    throw PipelineError.unsupportedCodec
                }
            case .audioConfig(let config):
                do {
                    let format = try SampleFactory.audioFormat(config: config)
                    audioFormat = format.description
                    audioSampleRate = format.sampleRate
                } catch {
                    throw PipelineError.unsupportedCodec
                }
            case .video(let frame):
                try handle(frame)
            case .audio(let frame):
                try handle(frame)
            }
        }
    }

    private func handle(_ frame: VideoFrame) throws {
        guard let format = videoFormat else { return }
        if baseTime == nil {
            guard frame.isKeyframe else { return }
            baseTime = frame.decodeTime
            settleStart = .now
            settleWindowStart = .now
            settleWindowPTS = .zero
        }
        let dts = frame.decodeTime - baseTime!
        let pts = dts + frame.compositionOffset
        let sample: CMSampleBuffer
        do {
            sample = try SampleFactory.videoSample(frame, format: format, pts: pts, dts: dts)
        } catch {
            throw PipelineError.unsupportedCodec
        }
        let time = CMTime(value: CMTimeValue(pts), timescale: 1000)
        if time > lastVideoPTS || !hasStarted { lastVideoPTS = time }
        if frame.isKeyframe {
            recentKeyframes.append(time)
            if recentKeyframes.count > Tuning.keyframeHistory { recentKeyframes.removeFirst() }
        }
        pendingVideo.append(sample)
        if !hasStarted {
            startIfSettled()
        } else if isVideoSuspended {
            if frame.isKeyframe { pendingVideo.drop(before: time) }
        } else {
            drainVideo()
        }
    }

    func setVideoSuspended(_ suspended: Bool) {
        guard suspended != isVideoSuspended else { return }
        isVideoSuspended = suspended
        if suspended {
            targets.video.stopRequestingMediaData()
            isRequestingVideo = false
        } else {
            drainVideo()
        }
        logInfo("视频\(suspended ? "暂停" : "恢复")")
    }

    private func startIfSettled() {
        guard !hasStarted, let first = settleStart, let windowStart = settleWindowStart else { return }
        let now = ContinuousClock.now
        let window = windowStart.duration(to: now)
        guard window >= Tuning.startSettleWindow else { return }
        let growth = (lastVideoPTS - settleWindowPTS).seconds
        if growth > window.seconds * Tuning.burstGrowthRatio, first.duration(to: now) < Tuning.startSettleLimit {
            settleWindowStart = now
            settleWindowPTS = lastVideoPTS
            return
        }
        let start = keyframe(keeping: reserve) ?? recentKeyframes.first ?? .zero
        pendingVideo.drop(before: start)
        pendingAudio.drop(before: start)
        hasStarted = true
        targets.synchronizer.setRate(0, time: start)
        drainVideo()
        drainAudio()
        logInfo("起播准备，丢掉突发缓存 \(start.seconds) 秒，余量目标 \(self.reserve) 秒")
        hold = (now, Tuning.startupHoldLimit)
        releaseHoldIfReady()
    }

    private var reserve: Double { Tuning.reserveLevels[reserveLevel] }

    private func keyframe(keeping reserve: Double) -> CMTime? {
        let limit = lastVideoPTS - CMTime(seconds: reserve, preferredTimescale: 1000)
        return recentKeyframes.last { $0 <= limit }
    }

    private func releaseHoldIfReady() {
        guard let hold else { return }
        let buffered = (lastVideoPTS - targets.synchronizer.currentTime()).seconds
        guard buffered >= reserve || hold.since.duration(to: .now) >= hold.limit else { return }
        self.hold = nil
        if state == .buffering {
            logInfo("缓冲恢复，停顿 \(hold.since.duration(to: .now).milliseconds) ms，缓冲 \(buffered) 秒")
        }
        targets.synchronizer.rate = targetRate
        reconnectAttempt = 0
        update(.playing)
        let elapsed = openedAt.duration(to: .now)
        logInfo("开始播放，距打开 \(elapsed.milliseconds) ms，缓冲 \(buffered) 秒")
    }

    private func handle(_ frame: AudioFrame) throws {
        guard let base = baseTime, let format = audioFormat, audioSampleRate > 0 else { return }
        let milliseconds = frame.time - base
        guard milliseconds >= 0 else { return }
        let rate = Int64(audioSampleRate)
        if let next = audioNextValue,
            abs(Int(next * 1000 / rate) - milliseconds) <= Tuning.audioRealignMilliseconds
        {
            audioNextValue = next + 1024
        } else {
            audioNextValue = Int64(milliseconds) * rate / 1000 + 1024
        }
        let value = audioNextValue! - 1024
        let sample: CMSampleBuffer
        do {
            sample = try SampleFactory.audioSample(
                frame.data, format: format, pts: CMTime(value: value, timescale: CMTimeScale(audioSampleRate)))
        } catch {
            throw PipelineError.unsupportedCodec
        }
        pendingAudio.append(sample)
        if hasStarted { drainAudio() }
    }

    private func deactivateRenderers() {
        targets.video.stopRequestingMediaData()
        targets.audio.stopRequestingMediaData()
        isRequestingVideo = false
        isRequestingAudio = false
    }

    private func drainVideo() {
        guard hasStarted, !isVideoSuspended else { return }
        while targets.video.isReadyForMoreMediaData, let sample = pendingVideo.popFirst() {
            targets.video.enqueue(sample)
        }
        if targets.video.status == .failed {
            if !rendererFailed { logError("视频渲染器失败：\(String(describing: targets.video.error))") }
            rendererFailed = true
        }
        if pendingVideo.isEmpty {
            if isRequestingVideo {
                targets.video.stopRequestingMediaData()
                isRequestingVideo = false
            }
        } else if !isRequestingVideo {
            isRequestingVideo = true
            targets.video.requestMediaDataWhenReady(on: queue) { [self] in
                assumeIsolated { $0.drainVideo() }
            }
        }
    }

    private func drainAudio() {
        guard hasStarted else { return }
        while targets.audio.isReadyForMoreMediaData, let sample = pendingAudio.popFirst() {
            targets.audio.enqueue(sample)
        }
        if targets.audio.status == .failed {
            if !rendererFailed { logError("音频渲染器失败：\(String(describing: targets.audio.error))") }
            rendererFailed = true
        }
        if pendingAudio.isEmpty {
            if isRequestingAudio {
                targets.audio.stopRequestingMediaData()
                isRequestingAudio = false
            }
        } else if !isRequestingAudio {
            isRequestingAudio = true
            targets.audio.requestMediaDataWhenReady(on: queue) { [self] in
                assumeIsolated { $0.drainAudio() }
            }
        }
    }

    private func resetConnection(removingImage: Bool) {
        targets.synchronizer.setRate(0, time: .zero)
        targets.video.flush(removingDisplayedImage: removingImage, completionHandler: nil)
        targets.audio.flush()
        demuxer = FLVDemuxer()
        videoFormat = nil
        audioFormat = nil
        audioSampleRate = 0
        baseTime = nil
        audioNextValue = nil
        pendingVideo = SampleQueue()
        pendingAudio = SampleQueue()
        lastVideoPTS = .zero
        recentKeyframes = []
        hold = nil
        lastChunkAt = nil
        hasStarted = false
        settleStart = nil
        settleWindowStart = nil
        targetRate = 1
        rendererFailed = false
    }

    private func monitor() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: Tuning.tickInterval) } catch { return }
            tick()
        }
    }

    private func tick() {
        if rendererFailed {
            currentStream?.cancel()
            return
        }
        if let last = lastChunkAt, last.duration(to: .now) >= Tuning.silenceLimit {
            logWarning("连续 \(Tuning.silenceLimit.seconds) 秒没收到数据，判为断流")
            lastChunkAt = nil
            currentStream?.cancel()
            return
        }
        guard hasStarted else {
            startIfSettled()
            return
        }
        if hold != nil {
            releaseHoldIfReady()
            return
        }
        guard state == .playing else { return }
        let synchronizer = targets.synchronizer
        let buffered = (lastVideoPTS - synchronizer.currentTime()).seconds
        let now = ContinuousClock.now

        if buffered < Tuning.underrun {
            stallCount += 1
            reserveLevel = min(reserveLevel + 1, Tuning.reserveLevels.count - 1)
            reserveChangedAt = now
            logInfo("缓冲耗尽，余量目标升到 \(self.reserve) 秒")
            synchronizer.rate = 0
            hold = (now, Tuning.refillHoldLimit)
            update(.buffering)
            return
        }
        if reserveLevel > 0, reserveChangedAt.duration(to: now) >= Tuning.reserveDecay {
            reserveLevel -= 1
            reserveChangedAt = now
        }
        logStatsIfDue(buffered: buffered, at: now)
        let excess = buffered - reserve
        if excess > Tuning.jumpMargin, let target = keyframe(keeping: reserve),
            target - synchronizer.currentTime() > Tuning.minJump
        {
            logInfo("积压 \(buffered) 秒，跳到余量 \(self.reserve) 秒处的关键帧")
            pendingVideo.drop(before: target)
            pendingAudio.drop(before: target)
            synchronizer.setRate(targetRate, time: target)
        } else if excess > Tuning.catchUpHigh, targetRate == 1 {
            targetRate = Tuning.catchUpRate
            synchronizer.rate = targetRate
        } else if excess < Tuning.catchUpLow, targetRate != 1 {
            targetRate = 1
            synchronizer.rate = 1
        }
    }

    private func logStatsIfDue(buffered: Double, at now: ContinuousClock.Instant) {
        let elapsed = statsAt.duration(to: now)
        guard elapsed >= Tuning.statsInterval else { return }
        let usage = ProcessUsage.current()
        let cpu = (usage.cpuSeconds - statsCPUSeconds) / elapsed.seconds * 100
        statsAt = now
        statsCPUSeconds = usage.cpuSeconds
        logInfo(
            "统计 缓冲 \(buffered) 秒，余量 \(reserve) 秒，倍速 \(Double(targetRate))，累计卡顿 \(stallCount) 次、重连 \(reconnectCount) 次；进程 CPU \(cpu)%，内存 \(usage.memoryMegabytes) MB"
        )
    }

    private func logInfo(_ message: LogMessage) {
        Self.logger.info("#\(id) \(message.text)")
    }

    private func logWarning(_ message: LogMessage) {
        Self.logger.warning("#\(id) \(message.text)")
    }

    private func logError(_ message: LogMessage) {
        Self.logger.error("#\(id) \(message.text)")
    }

    private func update(_ newState: PlaybackState) {
        guard newState != state else { return }
        switch newState {
        case .reconnecting, .ended, .failed: logInfo("状态 \(newState)")
        case .idle, .connecting, .playing, .buffering: break
        }
        state = newState
        states.yield(newState)
    }
}

private struct SampleQueue {
    private var items: [CMSampleBuffer] = []
    private var head = 0

    var isEmpty: Bool { head >= items.count }

    mutating func append(_ sample: CMSampleBuffer) { items.append(sample) }

    mutating func popFirst() -> CMSampleBuffer? {
        guard head < items.count else { return nil }
        defer {
            head += 1
            compact()
        }
        return items[head]
    }

    mutating func drop(before time: CMTime) {
        while head < items.count, CMSampleBufferGetPresentationTimeStamp(items[head]) < time { head += 1 }
        compact()
    }

    private mutating func compact() {
        guard head > 256, head * 2 > items.count else { return }
        items.removeSubrange(0..<head)
        head = 0
    }
}

extension Duration {
    fileprivate var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    fileprivate var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
