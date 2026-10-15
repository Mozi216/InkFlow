import Foundation
import InkFlowCore

struct LocalBroadcastSession: Codable {
    var id: String
    var expires: Date
    var appearance: Appearance
    var heartbeat = Date()
}

struct LocalBroadcastSnapshot: Codable {
    var sessionID: String
    var date: Date
    var processedSeconds: Double
    var state: LyricActivity.ContentState?
}

enum LocalBroadcastStore {
    static let notification = "com.inkflow.mobile.local-lyrics-updated"

    static let folder: URL? = {
        // A personal signer can rename the group. Read the groups actually granted
        // to this bundle instead of assuming the unsigned project's identifier.
        guard let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: profile),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String] else { return nil }
        for group in groups where group.hasPrefix("group.com.inkflow.mobile") {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return url }
        }
        return nil
    }()

    static func readSession() throws -> LocalBroadcastSession {
        let session: LocalBroadcastSession = try read("local-session.json")
        guard session.expires > Date(), Date().timeIntervalSince(session.heartbeat) < 25 else {
            throw RelayError.unavailable("本次歌词连接已结束，或主 App 的后台任务已停止。")
        }
        return session
    }

    static func save(_ session: LocalBroadcastSession) throws { try write(session, "local-session.json") }
    static func readSnapshot() throws -> LocalBroadcastSnapshot { try read("local-lyrics.json") }

    static func publish(_ snapshot: LocalBroadcastSnapshot) throws {
        try write(snapshot, "local-lyrics.json")
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: notification as CFString), nil, nil, true)
    }

    static func clear(id: String) {
        let stored: LocalBroadcastSession? = try? read("local-session.json")
        guard stored?.id == id, let folder else { return }
        for name in ["local-session.json", "local-lyrics.json"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func read<T: Decodable>(_ name: String) throws -> T {
        guard let folder else { throw RelayError.unavailable("当前签名未提供 InkFlow 的本机共享组。") }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: folder.appendingPathComponent(name)))
    }

    private static func write<T: Encodable>(_ value: T, _ name: String) throws {
        guard let folder else { throw RelayError.unavailable("当前签名未提供 InkFlow 的本机共享组。") }
        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent(name),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
