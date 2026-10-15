import SwiftUI

@main
struct InkFlowApp: App {
    @StateObject private var session = LyricSession()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--layout-check") {
                LayoutCheckView()
            } else { home }
            #else
            home
            #endif
        }
    }

    private var home: some View {
            HomeView(session: session)
                .preferredColorScheme(.dark)
                .tint(.white)
                .onChange(of: scenePhase) { _, phase in session.sceneChanged(phase) }
                .task { await session.handleConnectionRequest() }
                .onReceive(NotificationCenter.default.publisher(for: ConnectionRequest.notification)) { _ in
                    Task { await session.handleConnectionRequest() }
                }
                .onOpenURL { url in
                    if url.scheme == "inkflow", url.host == "connect" { ConnectionRequest.request() }
                }
    }
}
