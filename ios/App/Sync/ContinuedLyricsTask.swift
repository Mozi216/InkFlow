import BackgroundTasks
import Foundation

@MainActor final class ContinuedLyricsTask {
    static let duration = 30.0 * 60
    var onEnded: ((String) -> Void)?
    private var task: BGContinuedProcessingTask?
    private var identifier: String?
    private var pending: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?
    private var lastReportedSecond = 0

    func start() async throws {
        stop()
        let id = (Bundle.main.bundleIdentifier ?? "com.inkflow.mobile") + ".listening." + UUID().uuidString
        identifier = id
        // Register the exact identifier; older iOS 26 builds have a wildcard-handler matching bug.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
            Task { @MainActor in self?.started(task, identifier: id) }
        }
        guard registered else { identifier = nil; throw RelayError.unavailable("系统未能注册歌词后台任务。") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending = continuation
            let request = BGContinuedProcessingTaskRequest(identifier: id, title: "InkFlow 本机歌词同步",
                subtitle: "等待系统音频 · 本次最多分析 30 分钟")
            request.strategy = .fail
            do { try BGTaskScheduler.shared.submit(request) }
            catch { fail("系统暂时不能开始后台同步：" + error.localizedDescription); return }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard self?.identifier == id, self?.task == nil else { return }
                self?.fail("系统没有启动后台任务，本次连接未开始。")
            }
        }
    }

    func progress(processedSeconds: Double) {
        guard let task, processedSeconds.isFinite else { return }
        // Progress comes from PCM samples actually analyzed, not a keep-alive timer.
        let seconds = min(Self.duration, max(0, processedSeconds))
        let wholeSecond = Int(seconds)
        guard wholeSecond > lastReportedSecond else { return }
        lastReportedSecond = wholeSecond
        task.progress.completedUnitCount = Int64(seconds * 1000)
        if wholeSecond % 10 == 0 {
            task.updateTitle("InkFlow 本机歌词同步", subtitle: "已分析 \(wholeSecond / 60) 分 \(wholeSecond % 60) 秒 · 可随时停止")
        }
        if seconds >= Self.duration { stop(success: true); onEnded?("本次 30 分钟同步已完成，可重新开始。") }
    }

    func stop(success: Bool = false) {
        timeout?.cancel()
        timeout = nil
        if let id = identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id) }
        identifier = nil
        task?.setTaskCompleted(success: success)
        task = nil
        lastReportedSecond = 0
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: CancellationError())
    }

    private func started(_ received: BGTask, identifier id: String) {
        guard identifier == id, let received = received as? BGContinuedProcessingTask else {
            received.setTaskCompleted(success: false)
            return
        }
        timeout?.cancel()
        timeout = nil
        task = received
        received.progress.totalUnitCount = Int64(Self.duration * 1000)
        received.progress.completedUnitCount = 0
        received.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard self?.identifier == id else { return }
                self?.stop()
                self?.onEnded?("系统结束了本次后台同步，或你已在系统任务中停止。")
            }
        }
        let continuation = pending
        pending = nil
        continuation?.resume()
    }

    private func fail(_ message: String) {
        let continuation = pending
        pending = nil
        stop()
        continuation?.resume(throwing: RelayError.unavailable(message))
    }
}
