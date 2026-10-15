import SwiftUI
import WidgetKit
import ActivityKit

@main
struct InkFlowWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivity.self) { context in
            IslandArtwork(state: context.state, stale: context.isStale)
                .padding(.horizontal, 12)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    IslandArtwork(state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "pause.circle" : "waveform").foregroundStyle(.white)
            } compactTrailing: {
                Text(islandStatus(context.state, stale: context.isStale) ?? context.state.line.text)
                    .font(.caption2).lineLimit(1).frame(maxWidth: 70)
            } minimal: {
                Image(systemName: context.isStale ? "pause.circle" : "waveform")
            }
            .keylineTint(.white.opacity(0.35))
            .widgetURL(URL(string: "inkflow://lyrics"))
        }
    }
}

private func islandStatus(_ state: LyricActivity.ContentState, stale: Bool) -> String? {
    if stale { return state.source == .capture ? "同步已中断" : "预览未更新" }
    if state.complete == true { return "预览结束" }
    return nil
}

private struct IslandArtwork: View {
    let state: LyricActivity.ContentState
    let stale: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if stale {
            VStack(spacing: 8) {
                Image(systemName: "pause.circle").font(.title2)
                Text(islandStatus(state, stale: true) ?? "更新已中断").font(.subheadline)
                Text("返回 InkFlow 查看").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).frame(height: 136)
        } else if state.line.text.isEmpty {
            Image(systemName: "waveform").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).frame(height: 64)
                .accessibilityLabel("等待音乐")
        } else {
            LyricArtwork(state: state, time: state.position, systemTimedFill: true)
                .animation(reduceMotion ? nil : .linear(duration: 0.7), value: state.revision)
                .frame(height: 136)
                .id(state.line.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)),
                                        removal: .opacity.combined(with: .offset(y: -12))))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.44), value: state.line.id)
                .overlay(alignment: .bottom) {
                    if state.complete == true {
                        Text("预览结束").font(.caption2).foregroundStyle(.secondary)
                    }
                }
        }
    }
}
