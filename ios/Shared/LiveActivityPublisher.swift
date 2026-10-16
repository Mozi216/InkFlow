import ActivityKit
import Foundation

@MainActor final class LiveActivityPublisher {
    private var pending: (Activity<LyricActivity>, LyricActivity.ContentState, (LyricActivity.ContentState, Double) -> Void)?
    private var worker: Task<Void, Never>?

    @discardableResult
    func submit(_ state: LyricActivity.ContentState, to activity: Activity<LyricActivity>,
                completion: @escaping (LyricActivity.ContentState, Double) -> Void = { _, _ in }) -> LyricActivity.ContentState? {
        guard let content = Self.prepare(state, attributes: activity.attributes) else { return nil }
        pending = (activity, content, completion)
        guard worker == nil else { return content }
        worker = Task { [weak self] in
            guard let self else { return }
            // One update in flight. If it takes longer, send only the newest pending state.
            while let (activity, content, completion) = pending, !Task.isCancelled {
                pending = nil
                let started = ProcessInfo.processInfo.systemUptime
                await activity.update(ActivityContent(state: content, staleDate: content.staleDate))
                guard !Task.isCancelled else { break }
                completion(content, ProcessInfo.processInfo.systemUptime - started)
            }
            worker = nil
        }
        return content
    }

    static func prepare(_ state: LyricActivity.ContentState,
                        attributes: LyricActivity) -> LyricActivity.ContentState? {
        var content = state
        let encoder = JSONEncoder()
        func size() -> Int {
            (try? encoder.encode(content).count + encoder.encode(attributes).count) ?? .max
        }
        if size() >= 4_000 { content.artwork = nil }
        return size() < 4_000 ? content : nil
    }

    func cancel() async {
        pending = nil
        worker?.cancel()
        await worker?.value
        worker = nil
    }
}
