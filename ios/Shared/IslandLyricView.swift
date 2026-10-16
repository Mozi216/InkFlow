import SwiftUI

/// Used by the widget and the in-app preview, including size and line transitions.
struct IslandLyricView: View {
    static let width = 320.0
    static let height = 136.0
    let state: LyricActivity.ContentState
    var stale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if stale {
                VStack(spacing: 8) {
                    Image(systemName: "pause.circle").font(.title2)
                    Text(state.source == .preview ? "预览未更新" : "同步已中断")
                        .font(.subheadline)
                }.foregroundStyle(.secondary)
            } else if state.line.text.isEmpty {
                Text(state.message ?? "等待音乐")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LyricArtwork(state: state)
                    .id(state.line.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                            removal: .opacity.combined(with: .offset(y: -6))))
            }
        }
        .frame(maxWidth: Self.width)
        .frame(height: Self.height)
        .clipped(antialiased: true)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: state.line.id)
        .overlay(alignment: .bottom) {
            if state.complete == true {
                Text(state.source == .preview ? "预览结束" : "连接已结束")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
