import SwiftUI

@main
struct InkFlowApp: App {
    @StateObject private var session = LyricSession()
    var body: some Scene {
        WindowGroup {
            HomeView(session: session)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
