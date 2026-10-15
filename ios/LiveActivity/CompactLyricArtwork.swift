import SwiftUI
import InkFlowCore

struct SongArtwork: View {
    let state: LyricActivity.ContentState

    var body: some View {
        Group {
            if let data = state.artwork, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(LyricPalette.ink(state.appearance.theme).opacity(0.16))
                    Image(systemName: "music.note").font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentTransition(.identity)
        .animation(nil, value: state.revision)
        .accessibilityLabel(state.artwork == nil ? "歌曲封面暂不可用" : "歌曲封面")
    }
}

struct CompactLyricArtwork: View {
    let state: LyricActivity.ContentState
    let stale: Bool
    var width: Double = 70
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phrase = CompactLyrics.phrase(state.line, at: state.position)
        let words = StageLayout.tokens(phrase)
        let ink = LyricPalette.ink(state.appearance.theme)
        ZStack {
            if stale || phrase.text.isEmpty {
                Image(systemName: stale ? "pause.circle" : "waveform").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        let font = min(14, width / max(1, words.reduce(0) { $0 + $1.units }) * 0.85)
                        let placed = PlacedToken(token: word, x: 0, y: 0, font: font,
                                                 width: word.units * font, row: 0, index: index)
                        let fill = fillProgress(at: state.position, start: word.start, end: word.end)
                        let text = Text(word.text).font(.system(size: font, weight: .semibold))
                            .fixedSize().contentTransition(.identity)
                        ZStack(alignment: .leading) {
                            text.foregroundStyle(ink.opacity(0.32))
                            text.foregroundStyle(ink).mask(alignment: .leading) {
                                WordFillMask(token: placed, state: state, fraction: fill, timed: true)
                            }
                        }
                        .shadow(color: ink.opacity(0.35), radius: min(3, state.appearance.glow * 2))
                        .animation(nil, value: state.revision)
                    }
                }
                .id(phrase.id)
                .transition(.push(from: .bottom))
            }
        }
        .frame(width: width, height: 25)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phrase.id)
        .accessibilityLabel(stale ? "歌词更新已中断" : phrase.text)
    }
}
