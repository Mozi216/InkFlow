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
    // nil is the system's minimal presentation when another activity shares the island.
    var side: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        let phrase = side != nil && state.complete == true && StageLayout.fallbackWidth(state.line.text) <= 12
            ? state.line : CompactLyrics.phrase(state.line, at: state.position)
        let columns = CompactLyrics.columns(phrase)
        let reduce = reduceMotion || dimmed
        let movement = state.position + (state.playing && !reduce ? 1.25 : 0)
        ZStack {
            if stale || state.line.text.isEmpty {
                Image(systemName: stale ? "pause.circle" : "waveform").foregroundStyle(.secondary)
            } else {
                Group {
                    if let side {
                        if columns[side].text.isEmpty {
                            SongArtwork(state: state).frame(width: 22, height: 22)
                        } else { lettering(columns[side], width: 72, limit: 14) }
                    } else if columns[0].text.isEmpty {
                        lettering(columns[1], width: 42, limit: 13)
                    } else {
                        VStack(spacing: 0) {
                            lettering(columns[0], width: 42, limit: 11.5).frame(height: 13)
                            lettering(columns[1], width: 42, limit: 11.5).frame(height: 13)
                        }
                    }
                }
                .id(phrase.id)
                .offset(y: reduce ? 0 : sin(movement * 0.7 + Double(side ?? 0) * .pi) * 0.5)
                .rotationEffect(.degrees(reduce ? 0 : sin(movement * 0.55) * 0.65))
                .animation(state.playing && !reduce ? .linear(duration: 1.25) : nil, value: movement)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)),
                                        removal: .opacity.combined(with: .offset(y: -4))))
            }
        }
        .frame(width: side == nil ? 42 : 72, height: 27, alignment: .center)
        .clipped()
        .animation(reduce ? nil : .easeInOut(duration: 0.3), value: phrase.id)
        .accessibilityLabel(stale ? "歌词更新已中断" : phrase.text)
    }

    private func lettering(_ line: LyricLine, width: Double, limit: Double) -> some View {
        let baseFont = NativeTypesetting.font(size: 14, weight: 0.6, style: state.appearance.style)
        let words = StageLayout.tokens(line) {
            ($0 as NSString).size(withAttributes: [.font: baseFont]).width / 14
        }
        let space = (" " as NSString).size(withAttributes: [.font: baseFont]).width / 14
        let units = words.enumerated().reduce(0.0) { total, pair in
            total + pair.element.units + (pair.offset > 0 && pair.element.space ? space : 0)
        }
        let font = min(limit, (width - 6) / max(1, units))
        let ink = LyricPalette.ink(state.appearance.theme)
        return HStack(spacing: 0) {
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
                        WordFillMask(token: placed, state: state, fraction: fill, timed: !dimmed)
                    }
                }
                .shadow(color: ink.opacity(0.35), radius: min(3, state.appearance.glow * 2))
                .animation(nil, value: state.revision)
            }
        }.frame(width: width, alignment: .center)
    }
}
