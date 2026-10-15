import Foundation

@MainActor final class LocalBroadcastPublisher {
    var onFailure: ((String) -> Void)?
    private let sessionID: String
    private var state: LyricActivity.ContentState?
    private var processedSeconds = 0.0
    private var lastProgress = 0.0
    private var stopped = false

    init(sessionID: String) { self.sessionID = sessionID }

    func submit(_ state: LyricActivity.ContentState) {
        guard !stopped else { return }
        self.state = state
        publish()
    }

    func progress(_ seconds: Double) {
        guard !stopped else { return }
        processedSeconds = max(processedSeconds, seconds)
        guard seconds - lastProgress >= 1 else { return }
        lastProgress = seconds
        publish()
    }

    func finish(_ state: LyricActivity.ContentState?) async {
        guard !stopped else { return }
        self.state = state
        publish()
        stopped = true
    }

    private func publish() {
        do {
            try LocalBroadcastStore.publish(LocalBroadcastSnapshot(sessionID: sessionID,
                date: Date(), processedSeconds: processedSeconds, state: state))
        } catch {
            stopped = true
            onFailure?(error.localizedDescription)
        }
    }
}
