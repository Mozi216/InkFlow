import Foundation
import InkFlowCore

// Only the short-lived upload credential is shared with the audio extension.
// The APNs signing key stays on the server, and the setup key stays in the app.
struct BroadcastConnection: Codable {
    var id: String
    var uploadKey: String
    var server: URL
    var expires: Date
    var appearance: Appearance
}

enum BroadcastStore {
    static var folder: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "InkFlowRelayGroup") as? String,
              !group.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    static func read() throws -> BroadcastConnection {
        guard let folder else { throw RelayError.unavailable("安装包缺少音频扩展共享权限，需要重新签名。") }
        let connection = try JSONDecoder().decode(BroadcastConnection.self,
            from: Data(contentsOf: folder.appendingPathComponent("connection.json")))
        guard connection.expires > Date() else { throw RelayError.unavailable("连接已过期，请重新准备连接。") }
        return connection
    }

    static func write(_ connection: BroadcastConnection) throws {
        guard let folder else { throw RelayError.unavailable("安装包缺少音频扩展共享权限，需要重新签名。") }
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("connection.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func clear() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("connection.json"))
    }
}

enum RelayError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let reason): return reason }
    }
}

enum RelayRequest {
    static func send<T: Encodable>(_ value: T, server: URL, path: String,
                                    key: String, method: String = "POST") async throws -> Data {
        guard server.scheme == "https", server.host != nil, server.user == nil,
              server.password == nil else { throw RelayError.unavailable("推送连接必须使用 HTTPS。") }
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(value)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            // Don't put tokens, URLs, or server internals into user-visible errors.
            switch response.statusCode {
            case 401, 403: throw RelayError.unavailable("推送连接凭据无效，需要重新配置。")
            case 404, 410: throw RelayError.unavailable("推送连接已失效，请重新准备连接。")
            case 413: throw RelayError.unavailable("这句歌词超过灵动岛推送容量。")
            case 429: throw RelayError.unavailable("推送服务正在限流，请稍后连接。")
            default: throw RelayError.unavailable("推送服务暂时不可用（\(response.statusCode)）。")
            }
        }
        return data
    }
}
