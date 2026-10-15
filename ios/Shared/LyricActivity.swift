import ActivityKit
import InkFlowCore
import Foundation

struct LyricActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var line: LyricLine
        var next: LyricLine?
        var appearance: Appearance
        var anchorDate: Date
        var position: Double
        var playing: Bool
        var waiting: Bool
        var repeated: Bool
        var revision: Int

        static func waiting(appearance: Appearance) -> Self {
            Self(line: LyricLine("", start: 0, end: 0), next: nil,
                 appearance: appearance, anchorDate: Date(), position: 0,
                 playing: false, waiting: true, repeated: false, revision: 0)
        }

        func time(at date: Date) -> Double {
            position + (playing ? max(0, date.timeIntervalSince(anchorDate)) : 0)
        }

        func date(for lyricTime: Double) -> Date {
            anchorDate.addingTimeInterval(lyricTime - position)
        }
    }
    var song: String
}
