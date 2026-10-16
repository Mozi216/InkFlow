#if DEBUG
import SwiftUI
import InkFlowCore

/// Frozen inputs for visual inspection of the shared island content.
struct SceneCheckView: View {
    private var style: LyricStyle {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--preview-style"), index + 1 < args.count else { return .flow }
        return LyricStyle(rawValue: args[index + 1]) ?? .flow
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(style.title).font(.headline)
            sample("让风穿过安静的窗", next: "把这一刻，轻轻留下", position: 2.6, theme: "white")
            sample("Let the light stay with us", next: "Until the morning comes", position: 4, theme: "cream")
            sample("光と影を重ねて", next: "静かな夜の中で", position: 6, theme: "rose")
        }
        .padding(20).preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.06))
    }

    private func sample(_ text: String, next: String, position: Double, theme: String) -> some View {
        var appearance = Appearance()
        appearance.style = style
        appearance.theme = theme
        let state = LyricActivity.ContentState(line: LyricLine(text, start: 0, end: 8),
            next: LyricLine(next, start: 9, end: 14), appearance: appearance,
            anchorDate: Date(timeIntervalSince1970: 0), position: position, playing: false,
            waiting: false, repeated: false, revision: 1)
        return VStack(spacing: 8) {
            IslandLyricView(state: state)
                .background(.black, in: RoundedRectangle(cornerRadius: 24))
            HStack(spacing: 24) {
                CompactLyricArtwork(state: state, stale: false)
                CompactLyricArtwork(state: state, stale: false, minimal: true)
            }
        }
    }
}
#endif
