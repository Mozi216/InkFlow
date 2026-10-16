import SwiftUI

struct IslandPreview: View {
    let state: LyricActivity.ContentState
    var stale = false
    @State private var compact = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("灵动岛预览", selection: $compact) {
                Text("展开").tag(false)
                Text("收起").tag(true)
            }.pickerStyle(.segmented).frame(width: 160)

            Group {
                if compact {
                    HStack(spacing: 0) {
                        CompactLyricArtwork(state: state, stale: stale)
                        Color.clear.frame(width: 126, height: 27)
                        SongArtwork(state: state).frame(width: 20, height: 20)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black, in: Capsule())
                    .frame(height: IslandLyricView.height)
                } else {
                    IslandLyricView(state: state, stale: stale)
                }
            }.frame(maxWidth: .infinity)
        }
    }
}
