import Foundation
import InkFlowCore

@MainActor final class LocalBroadcastBridge {
    var onUpdate: ((LocalBroadcastSnapshot) -> Void)?
    var onEnded: ((String) -> Void)?
    private let background = ContinuedLyricsTask()
    private var session: LocalBroadcastSession?
    private var observerInstalled = false

    static var unavailableReason: String? {
        LocalBroadcastStore.folder == nil ? "当前安装包缺少本机共享组；需用 iLoader 为完整包重新签名。此方案不需要推送权限。" : nil
    }

    func prepare(appearance: Appearance) async throws {
        stop()
        if !observerInstalled {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(), { _, observer, _, _, _ in
                    guard let observer else { return }
                    let bridge = Unmanaged<LocalBroadcastBridge>.fromOpaque(observer).takeUnretainedValue()
                    Task { @MainActor [weak bridge] in bridge?.receive() }
                }, LocalBroadcastStore.notification as CFString, nil, .deliverImmediately)
            observerInstalled = true
        }
        background.onEnded = { [weak self] message in self?.stop(); self?.onEnded?(message) }
        try await background.start()
        let created = LocalBroadcastSession(id: UUID().uuidString,
            expires: Date().addingTimeInterval(ContinuedLyricsTask.duration + 60), appearance: appearance)
        do { try LocalBroadcastStore.save(created); session = created }
        catch { background.stop(); throw error }
    }

    func updateAppearance(_ appearance: Appearance) {
        guard var session else { return }
        session.appearance = appearance
        do { try LocalBroadcastStore.save(session); self.session = session }
        catch { stop(); onEnded?(error.localizedDescription) }
    }

    func stop() {
        background.stop()
        if let session { LocalBroadcastStore.clear(id: session.id) }
        session = nil
    }

    func receive() {
        guard var session, let snapshot = try? LocalBroadcastStore.readSnapshot(),
              snapshot.sessionID == session.id, Date().timeIntervalSince(snapshot.date) < 5 else { return }
        if Date().timeIntervalSince(session.heartbeat) >= 5 {
            session.heartbeat = Date()
            do { try LocalBroadcastStore.save(session); self.session = session }
            catch { stop(); onEnded?(error.localizedDescription); return }
        }
        background.progress(processedSeconds: snapshot.processedSeconds)
        onUpdate?(snapshot)
    }

    deinit {
        if observerInstalled {
            CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque())
        }
    }
}
