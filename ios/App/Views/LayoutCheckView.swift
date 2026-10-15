#if DEBUG
import SwiftUI
import InkFlowCore

/// Same views as the widget, on a screenshotable surface. This does not test WidgetKit scheduling.
struct LayoutCheckView: View {
    var body: some View {
        VStack(spacing: 22) {
            Text("Compact layout checks").font(.headline)
            row("灯光落下，预览到这里", position: 9, complete: false)
            row("灯光落下，预览到这里", position: 10, complete: true)
            row("Let the light stay with us", position: 6, complete: false)
            BroadcastConnectionView()
        }
        .padding(20).preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
    }

    private func row(_ text: String, position: Double, complete: Bool) -> some View {
        let state = LyricActivity.ContentState(line: LyricLine(text, start: 0, end: 10), next: nil,
            appearance: Appearance(), anchorDate: Date(), position: position, playing: false,
            waiting: false, repeated: false, revision: 1, complete: complete)
        return VStack(spacing: 8) {
            Text(text).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                CompactLyricArtwork(state: state, stale: false, side: 0)
                Color.clear.frame(width: 126, height: 27)
                CompactLyricArtwork(state: state, stale: false, side: 1)
            }.padding(6).background(.black, in: Capsule())
            CompactLyricArtwork(state: state, stale: false)
                .padding(5).background(.black, in: Capsule())
        }
    }
}
#endif
