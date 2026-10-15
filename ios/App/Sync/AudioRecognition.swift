import AVFoundation

final class AudioRecognition {
    let queue = DispatchQueue(label: "InkFlow.audio", qos: .userInitiated)
    var onMatch: ((SongMatch) -> Void)?
    var onLevel: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    var onProgress: ((Double) -> Void)?
    private let matcher = NetEaseAudioMatcher()
    private var request: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private let output = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
    private var audio: [Float] = []
    private let windowFrames = 96_000
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
        if now - lastMeter >= 0.25 {
            lastMeter = now
            onLevel?(level, now)
            onProgress?(processedSeconds)
        }
        if now - lastBuffer > 0.6 { clearWindow() }
        lastBuffer = now
        if level > 0.00001 { lastSound = now }
        if now - lastSound > 1.5 {
            if !audio.isEmpty || request != nil { clearWindow() }
            return
        }
        audio.append(contentsOf: UnsafeBufferPointer(start: samples, count: count))
        if audio.count > windowFrames { audio.removeFirst(audio.count - windowFrames) }
        guard audio.count == windowFrames, request == nil, now >= nextAttempt else { return }
        let pcm = audio.withUnsafeBytes { Data($0) }
        let startUptime = now - 12
        let expectedGeneration = generation
        nextAttempt = now + 4
        request = Task { [weak self, matcher] in
            do {
                let match = try await matcher.match(pcm: pcm, startUptime: startUptime)
                try Task.checkCancellation()
                self?.queue.async { [weak self] in
                    guard let self, self.active, self.generation == expectedGeneration else { return }
                    self.request = nil
                    if let match { self.onMatch?(match) }
                }
            } catch {
                let cancelled = Task.isCancelled
                self?.queue.async { [weak self] in
                    guard let self, self.active, self.generation == expectedGeneration else { return }
                    self.request = nil
                    if !cancelled { self.onError?(error.localizedDescription) }
                }
            }
        }
    }
}
