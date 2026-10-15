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
    let side: Int
    private let width = 72.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phrase = state.complete == true && StageLayout.fallbackWidth(state.line.text) <= 12
            ? state.line : CompactLyrics.phrase(state.line, at: state.position)
        let column = CompactLyrics.columns(phrase)[side]
        let baseFont = NativeTypesetting.font(size: 14, weight: 0.6, style: state.appearance.style)
        let words = StageLayout.tokens(column) {
            ($0 as NSString).size(withAttributes: [.font: baseFont]).width / 14
        }
        let space = (" " as NSString).size(withAttributes: [.font: baseFont]).width / 14
        let units = words.enumerated().reduce(0.0) { total, pair in
            total + pair.element.units + (pair.offset > 0 && pair.element.space ? space : 0)
        }
        let font = min(14, (width - 8) / max(1, units))
        let ink = LyricPalette.ink(state.appearance.theme)
        let movement = state.playing && !reduceMotion ? state.position + 1.25 : state.position
        ZStack {
            if stale || state.line.text.isEmpty {
                Image(systemName: stale ? "pause.circle" : "waveform").foregroundStyle(.secondary)
            } else if column.text.isEmpty {
                SongArtwork(state: state).frame(width: 22, height: 22)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        if index > 0 && word.space { Color.clear.frame(width: font * space, height: 1) }
                        let placed = PlacedToken(token: word, x: 0, y: 0, font: font,
                                                 width: word.units * font, row: 0, index: index)
                        let fill = fillProgress(at: state.position, start: word.start, end: word.end)
                        let text = Text(word.text).font(Font(baseFont.withSize(font)))
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
                .offset(y: reduceMotion ? 0 : sin(movement * 0.7 + Double(side) * .pi) * 0.65)
                .rotationEffect(.degrees(reduceMotion ? 0 : sin(movement * 0.55) * 0.65))
                .animation(state.playing && !reduceMotion ? .linear(duration: 1.25) : nil, value: movement)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)),
                                        removal: .opacity.combined(with: .offset(y: -4))))
            }
        }
        .frame(width: width, height: 27, alignment: .center)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: phrase.id)
        .accessibilityLabel(stale ? "歌词更新已中断" : phrase.text)
    }
}
