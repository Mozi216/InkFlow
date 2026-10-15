import AppIntents
import ActivityKit
import Foundation

struct ConnectLyricsIntent: AppIntent {
    static var title: LocalizedStringResource = "准备网易云歌词"
    static var description = IntentDescription("打开音频连接入口。仍需在系统面板确认音频采集，不会静默录制。")
    static var supportedModes: IntentModes { .foreground(.dynamic) }

    @MainActor func perform() async throws -> some IntentResult {
        let connected = Activity<LyricActivity>.activities.contains {
            $0.content.state.connectionActive == true && $0.activityState == .active
                && Date().timeIntervalSince($0.content.state.anchorDate) < 12
        }
        if connected { return .result() }
        try await continueInForeground(nil, alwaysConfirm: false)
        ConnectionRequest.request()
        return .result()
    }
}

struct InkFlowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ConnectLyricsIntent(),
                    phrases: ["用 \(.applicationName) 连接歌词"],
                    shortTitle: "准备网易云歌词", systemImageName: "waveform")
    }
}

enum ConnectionRequest {
    static let notification = Notification.Name("InkFlowPrepareConnection")
    private static let key = "prepareConnectionRequested"

    static func request() {
        UserDefaults.standard.set(true, forKey: key)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    static func consume() -> Bool {
        guard UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return true
    }
}
