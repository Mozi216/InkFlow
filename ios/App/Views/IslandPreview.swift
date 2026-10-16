import SwiftUI

struct IslandPreview: View {
    let state: LyricActivity.ContentState
    var stale = false
    @State private var presentation = 0

    var body: some View {
        VStack(spacing: 12) {
            Picker("灵动岛预览", selection: $presentation) {
                Text("展开").tag(0)
                Text("收起").tag(1)
                Text("最小").tag(2)
            }.pickerStyle(.segmented).frame(width: 220)

            Group {
                if presentation == 2 {
                    CompactLyricArtwork(state: state, stale: stale, minimal: true)
                        .padding(6).background(.black, in: Capsule())
                        .frame(height: IslandLyricView.height)
                } else if presentation == 1 {
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
