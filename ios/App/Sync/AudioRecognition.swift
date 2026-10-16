import AVFoundation
import OSLog
import InkFlowCore

final class AudioRecognition {
    let queue = DispatchQueue(label: "InkFlow.audio", qos: .userInitiated)
    var onMatch: ((SongMatch) -> Void)?
    var onLevel: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onProgress: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?
    var onUncertain: ((String) -> Void)?
    private let logger = Logger(subsystem: "com.inkflow.mobile", category: "AudioInput")
    private let matcher = NetEaseAudioMatcher()
    private var request: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private let output = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
    private var audio: [Float] = []
    private let windowFrames = 96_000
    private var windowSeconds = 6
    private var missedWindows = 0
    private var serviceFailures = 0
    private var tracker = RecognitionTracker()
    private var hasPublishedMatch = false
    private var lastAcceptedEnd = 0.0
    private var lastStatus = ""
    private var nextAttempt = 0.0
    private var lastMeter = 0.0
    private var lastSound = 0.0
    private var lastBuffer = 0.0
    private var processedSeconds = 0.0
    private var generation = 0
    private var active = false

    func reset() {
        queue.async {
            self.clearWindow()
            self.converter = nil
            self.lastBuffer = 0
            self.lastStatus = ""
            self.active = true
        }
    }

    func stop() {
        queue.async {
            self.active = false
            self.clearWindow()
            self.converter = nil
        }
    }

    private func clearWindow() {
        generation += 1
        request?.cancel()
        request = nil
        audio.removeAll(keepingCapacity: true)
        nextAttempt = 0
        windowSeconds = 6
        missedWindows = 0
        serviceFailures = 0
        tracker.reset()
    }

    private func report(_ message: String) {
        guard message != lastStatus else { return }
        lastStatus = message
        onStatus?(message)
    }

    private func invalidate(_ message: String) {
        if hasPublishedMatch {
            hasPublishedMatch = false
            onUncertain?(message)
        }
        report(message)
    }

    // Both capture drivers call this on queue. Only an in-memory audio window is kept.
    func consume(_ sample: CMSampleBuffer) {
        guard active, sample.isValid, let description = sample.formatDescription,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: basic) else { return }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, frames < 192_000,
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        input.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: input.mutableAudioBufferList) == noErr else { return }
        if converter?.inputFormat != format {
            clearWindow()
            converter = AVAudioConverter(from: format, to: output)
        }
        guard let converter,
              let buffer = AVAudioPCMBuffer(pcmFormat: output,
                frameCapacity: AVAudioFrameCount(ceil(Double(frames) * output.sampleRate / format.sampleRate)) + 32) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: buffer, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var sum = 0.0
        for index in 0..<count { sum += Double(samples[index] * samples[index]) }
        let level = sqrt(sum / Double(count))
        let now = ProcessInfo.processInfo.systemUptime
        processedSeconds += Double(count) / output.sampleRate
        if lastBuffer > 0, now - lastBuffer > 0.6 {
            logger.info("Audio gap \(now - self.lastBuffer) s; discard incomplete window")
            clearWindow()
        }
        lastBuffer = now
        if level > 0.00001 { lastSound = now }
        if now - lastSound < 1.5, hasPublishedMatch, now - lastAcceptedEnd > 8 {
            _ = tracker.expire(at: now)
            invalidate("当前歌曲尚未确认，正在重新识别")
        }
        // Invalidate first: the level callback must not resume an expired song for one frame.
        if now - lastMeter >= 0.25 {
            lastMeter = now
            onLevel?(level, now)
            onProgress?(processedSeconds)
        }
        if now - lastSound > 1.5 {
            if !audio.isEmpty || request != nil { clearWindow() }
            report("音频通道已连接，目前收到的是静音")
            return
        }
        audio.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        if audio.count > windowFrames { audio.removeFirst(audio.count - windowFrames) }
        let neededFrames = windowSeconds * 8_000
        if audio.count < neededFrames {
            report("已收到声音，正在采样 \(audio.count / 8_000)/\(windowSeconds) 秒")
            return
        }
        guard request == nil, now >= nextAttempt else { return }
        let window = Array(audio.suffix(neededFrames))
        let pcm = window.withUnsafeBytes { Data($0) }
        let startUptime = now - Double(windowSeconds)
        let expectedGeneration = generation
        nextAttempt = now + 2
        report("已收到声音，正在匹配歌曲")
        request = Task { [weak self, matcher] in
            do {
                let matches = try await matcher.match(pcm: pcm, startUptime: startUptime)
                try Task.checkCancellation()
                self?.queue.async { [weak self] in
                    guard let self, self.active, self.generation == expectedGeneration else { return }
                    self.request = nil
                    self.serviceFailures = 0
                    let decision = self.tracker.observe(matches.map(\.candidate), start: startUptime,
                        duration: Double(pcm.count) / 32_000, now: ProcessInfo.processInfo.systemUptime)
                    switch decision {
                    case .accepted(let candidate):
                        guard let match = matches.first(where: { $0.song.id == candidate.id }) else { return }
                        self.windowSeconds = 6
                        self.missedWindows = 0
                        self.hasPublishedMatch = true
                        self.lastAcceptedEnd = startUptime + Double(pcm.count) / 32_000
                        self.report("已识别：" + match.title)
                        self.logger.info("Confirmed id \(match.song.id), position \(match.position) from advancing audio windows")
                        self.onMatch?(match)
                    case .confirming:
                        self.windowSeconds = 6
                        self.invalidate("正在核对歌曲与播放位置")
                    case .ambiguous:
                        self.missedWindows += 1
                        self.windowSeconds = self.missedWindows.isMultiple(of: 2) ? 6 : 9
                        self.invalidate("识曲结果存在不同版本，暂不显示未确认歌词")
                    case .unmatched:
                        self.missedWindows += 1
                        // Always return to the recent six seconds after a longer probe.
                        self.windowSeconds = self.missedWindows.isMultiple(of: 2) ? 6 : min(12, 6 + self.missedWindows * 3)
                        if self.missedWindows >= 2 { self.invalidate("尚未匹配到当前歌曲，继续识别") }
                        else { self.report("尚未匹配到当前歌曲，继续识别") }
                    case .outdated:
                        self.report("识曲响应已过期，正在匹配最新音频")
                    }
                }
            } catch {
                let cancelled = Task.isCancelled
                self?.queue.async { [weak self] in
                    guard let self, self.active, self.generation == expectedGeneration else { return }
                    self.request = nil
                    if !cancelled {
                        self.serviceFailures += 1
                        let backoff = min(30.0, pow(2, Double(min(5, self.serviceFailures + 1))))
                        self.nextAttempt = ProcessInfo.processInfo.systemUptime + backoff
                        self.onError?(error.localizedDescription)
                    }
                }
            }
        }
    }
}
