import Foundation

@MainActor final class BroadcastPublisher {
    var onFailure: ((String) -> Void)?
    private let connection: BroadcastConnection
    private var pending: LyricActivity.ContentState?
    private var worker: Task<Void, Never>?
    private var sequence = 0
    private var stopped = false

    init(connection: BroadcastConnection) { self.connection = connection }

    func submit(_ state: LyricActivity.ContentState) {
        guard !stopped else { return }
        pending = state
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            defer { worker = nil }
            do {
                while let state = pending, !Task.isCancelled {
                    pending = nil
                    sequence += 1
                    _ = try await RelayRequest.send(Update(sequence: sequence, state: state),
                        server: connection.server, path: "sessions/\(connection.id)/updates", key: connection.uploadKey)
                }
            } catch {
                guard !Task.isCancelled else { return }
                stopped = true
                pending = nil
                onFailure?(error.localizedDescription)
            }
        }
    }

    func finish(_ state: LyricActivity.ContentState?) async {
        stopped = true
        pending = nil
        worker?.cancel()
        await worker?.value
        worker = nil
        // The server also expires abandoned sessions. An OS kill need not call this method.
        _ = try? await RelayRequest.send(End(state: state), server: connection.server,
            path: "sessions/\(connection.id)/end", key: connection.uploadKey)
    }

    private struct Update: Encodable { var sequence: Int; var state: LyricActivity.ContentState }
    private struct End: Encodable { var state: LyricActivity.ContentState? }
}
