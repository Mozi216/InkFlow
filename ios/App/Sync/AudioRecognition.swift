import AVFoundation
import ShazamKit

struct SongMatch {
    let title: String
    let artist: String
    let position: Double
    let uptime: Double
}

final class AudioRecognition: NSObject, SHSessionDelegate {
    let queue = DispatchQueue(label: "InkFlow.audio", qos: .userInitiated)
    var onMatch: ((SongMatch) -> Void)?
    var onLevel: ((Double, Double) -> Void)?
    var onError: ((String) -> Void)?
    private var session: SHSession?
    private var converter: AVAudioConverter?
    private let output = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var lastMeter = 0.0
    private var sampleTime: AVAudioFramePosition = 0

    func reset() {
        queue.async {
            let session = SHSession()
            session.delegate = self
            self.session = session
            self.converter = nil
            self.sampleTime = 0
        }
    }

    func stop() {
        queue.async { self.session?.delegate = nil; self.session = nil; self.converter = nil }
    }

    // Called on queue by ScreenCaptureKit. No audio or screen content is saved.
    func consume(_ sample: CMSampleBuffer) {
        guard let session, sample.isValid, let description = sample.formatDescription,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: basic) else { return }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, frames < 192_000,
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        input.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                           into: input.mutableAudioBufferList) == noErr else { return }
        if converter?.inputFormat != format { converter = AVAudioConverter(from: format, to: output) }
        guard let converter,
              let buffer = AVAudioPCMBuffer(pcmFormat: output,
                frameCapacity: AVAudioFrameCount(ceil(Double(frames) * output.sampleRate / format.sampleRate)) + 32) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: buffer, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        guard error == nil, buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { return }
        var sum = 0.0
        for index in 0..<Int(buffer.frameLength) { sum += Double(samples[index] * samples[index]) }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMeter >= 0.25 {
            lastMeter = now
            onLevel?(sqrt(sum / Double(buffer.frameLength)), now)
        }
        session.matchStreamingBuffer(buffer, at: AVAudioTime(sampleTime: sampleTime, atRate: output.sampleRate))
        sampleTime += AVAudioFramePosition(buffer.frameLength)
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        queue.async {
            guard session === self.session, let item = match.mediaItems.first,
                  let title = item.title, let artist = item.artist else { return }
            self.onMatch?(SongMatch(title: title, artist: artist, position: item.predictedCurrentMatchOffset,
                                   uptime: ProcessInfo.processInfo.systemUptime))
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        queue.async {
            guard session === self.session else { return }
            if let error { self.onError?(error.localizedDescription) }
        }
    }
}
