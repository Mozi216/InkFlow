import UIKit

@MainActor final class PreviewBackgroundTask {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin(onExpiration: @escaping @MainActor () -> Void) -> Bool {
        guard identifier == .invalid else { return true }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Finish 20-second island preview") { [weak self] in
            Task { @MainActor in
                self?.end()
                onExpiration()
            }
        }
        return identifier != .invalid
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
