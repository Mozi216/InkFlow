import SwiftUI
import WidgetKit
import ActivityKit

@main
struct InkFlowWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivity.self) { context in
            IslandArtwork(state: context.state)
                .padding(.horizontal, 12)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    IslandArtwork(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(.white)
            } compactTrailing: {
                Text(context.state.line.text).font(.caption2).lineLimit(1).frame(maxWidth: 70)
            } minimal: {
                Image(systemName: "waveform")
            }
            .keylineTint(.white.opacity(0.35))
            .widgetURL(URL(string: "inkflow://lyrics"))
        }
    }
}

private struct IslandArtwork: View {
    let state: LyricActivity.ContentState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if state.line.text.isEmpty {
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
        }
    }
}
