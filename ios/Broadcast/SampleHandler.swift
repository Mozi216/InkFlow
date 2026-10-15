import ReplayKit
import OSLog

final class SampleHandler: RPBroadcastSampleHandler {
    private let recognition = AudioRecognition()
    private var session: BroadcastLyrics?
    private var lastHealthCheck = 0.0
    private let logger = Logger(subsystem: "com.inkflow.mobile", category: "Broadcast")

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let session = BroadcastLyrics(recognition: recognition)
            session.onFailure = { [weak self] message in
                self?.logger.error("Connection failed: \(message, privacy: .public)")
                self?.finishBroadcastWithError(NSError(domain: "InkFlow.Broadcast", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]))
            }
            self.session = session
            session.start()
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // No video or microphone processing, recording or upload.
        if sampleBufferType == .audioApp {
            recognition.queue.async { [recognition] in recognition.consume(sampleBuffer) }
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastHealthCheck >= 3 {
            lastHealthCheck = now
            Task { @MainActor in session?.checkConnection() }
        }
    }

    override func broadcastPaused() {
        Task { @MainActor in session?.pause() }
    }

    override func broadcastResumed() {
        Task { @MainActor in session?.resume() }
    }

    override func broadcastFinished() {
        recognition.stop()
        Task { @MainActor in await session?.stop(); session = nil }
    }
}
