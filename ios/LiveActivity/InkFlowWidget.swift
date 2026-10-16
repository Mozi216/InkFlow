import SwiftUI
import WidgetKit
import ActivityKit

@main
struct InkFlowWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivity.self) { context in
            IslandLyricView(state: context.state, stale: context.isStale)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    IslandLyricView(state: context.state, stale: context.isStale)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                CompactLyricArtwork(state: context.state, stale: context.isStale)
            } compactTrailing: {
                SongArtwork(state: context.state).frame(width: 20, height: 20)
            } minimal: {
                CompactLyricArtwork(state: context.state, stale: context.isStale, minimal: true)
            }
            .keylineTint(.white.opacity(0.35))
            .widgetURL(URL(string: "inkflow://lyrics"))
        }
    }
}
