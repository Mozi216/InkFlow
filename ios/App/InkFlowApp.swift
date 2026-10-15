import SwiftUI

@main
struct InkFlowApp: App {
    @StateObject private var session = LyricSession()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            HomeView(session: session)
                .preferredColorScheme(.dark)
                .tint(.white)
                .onChange(of: scenePhase) { _, phase in session.sceneChanged(phase) }
        }
    }
}
