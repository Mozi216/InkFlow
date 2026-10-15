import ActivityKit
import Foundation
import InkFlowCore

@MainActor final class BroadcastRelay {
    var onFailure: ((String) -> Void)?
    private var tokenUpdates: Task<Void, Never>?
    private var connection: BroadcastConnection?
    private var generation = 0

    static var unavailableReason: String? {
        guard BroadcastStore.folder != nil else {
            return "此签名不支持 iOS 26 的后台歌词连接，需要包含 App Groups 和推送权限的开发者签名。预览仍可使用。"
        }
        guard let configuration = RelayConfiguration.load(), (try? configuration.validate()) != nil else {
            return "尚未配置歌词推送服务，请先导入连接配置。"
        }
        return nil
    }

    func prepare(_ activity: Activity<LyricActivity>, appearance: Appearance) async throws {
        generation += 1
        let attempt = generation
        guard let configuration = RelayConfiguration.load() else {
            throw RelayError.unavailable("尚未配置歌词推送服务。")
        }
        try configuration.validate()
        let token = try await firstToken(activity)
        guard attempt == generation else { throw CancellationError() }
        let data = try await RelayRequest.send(Registration(token: token.hex,
            bundleID: Bundle.main.bundleIdentifier ?? "", state: activity.content.state), server: configuration.server,
            path: "sessions", key: configuration.accessKey)
        let registered = try JSONDecoder().decode(RegistrationResult.self, from: data)
        // APNs accepting a request is not proof that iOS decoded or displayed it.
        // Require its marker to return through ActivityKit before permitting audio capture.
        do {
            guard attempt == generation else { throw CancellationError() }
            try await confirmDelivery(activity, id: registered.id)
            guard attempt == generation else { throw CancellationError() }
        }
        catch {
            _ = try? await RelayRequest.send([String: String](), server: configuration.server,
                path: "sessions/\(registered.id)/end", key: registered.uploadKey)
            throw error
        }
        let connection = BroadcastConnection(id: registered.id, uploadKey: registered.uploadKey,
            server: configuration.server, expires: Date(timeIntervalSince1970: registered.expires),
            appearance: appearance)
        // Save only after APNs token registration succeeds; only then reveal the broadcast picker.
        self.connection = connection
        try BroadcastStore.write(connection)
        observeTokens(activity, connection: connection)
    }

    func restore(_ activity: Activity<LyricActivity>) {
        guard let saved = try? BroadcastStore.read() else { return }
        connection = saved
        observeTokens(activity, connection: saved)
    }

    func updateAppearance(_ appearance: Appearance) {
        guard var connection else { return }
        connection.appearance = appearance
        do { try BroadcastStore.write(connection); self.connection = connection }
        catch { onFailure?(error.localizedDescription) }
    }

    func stop() async {
        generation += 1
        tokenUpdates?.cancel()
        tokenUpdates = nil
        let old = connection
        connection = nil
        BroadcastStore.clear()
        if let old {
            _ = try? await RelayRequest.send([String: String](), server: old.server,
                path: "sessions/\(old.id)/end", key: old.uploadKey)
        }
    }

    private func observeTokens(_ activity: Activity<LyricActivity>, connection: BroadcastConnection) {
        tokenUpdates?.cancel()
        tokenUpdates = Task { [weak self] in
            do {
                for await token in activity.pushTokenUpdates {
                    try Task.checkCancellation()
                    _ = try await RelayRequest.send(["token": token.hex], server: connection.server,
                        path: "sessions/\(connection.id)/token", key: connection.uploadKey)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.onFailure?(error.localizedDescription)
            }
        }
    }

    private func firstToken(_ activity: Activity<LyricActivity>) async throws -> Data {
        if let token = activity.pushToken { return token }
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                for await token in activity.pushTokenUpdates { return token }
                throw RelayError.unavailable("系统没有提供实时活动推送令牌。")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(12))
                throw RelayError.unavailable("未取得推送权限，请检查签名的 Push Notifications 配置及网络。")
            }
            defer { group.cancelAll() }
            guard let token = try await group.next() else { throw CancellationError() }
            return token
        }
    }

    private func confirmDelivery(_ activity: Activity<LyricActivity>, id: String) async throws {
        if activity.content.state.relaySession == id { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for await content in activity.contentUpdates where content.state.relaySession == id { return }
                throw RelayError.unavailable("实时活动已结束，无法确认推送。")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw RelayError.unavailable("服务已提交推送，但手机尚未收到；连接未启动。")
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    private struct Registration: Encodable { var token: String; var bundleID: String; var state: LyricActivity.ContentState }
    private struct RegistrationResult: Decodable { var id: String; var uploadKey: String; var expires: Double }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
