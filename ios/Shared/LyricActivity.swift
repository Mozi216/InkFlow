import ActivityKit
import InkFlowCore
import Foundation

struct LyricActivity: ActivityAttributes {
    enum Source: String, Codable {
        case preview, capture, broadcast
    }

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
        // Optional so an activity created by an older build can still be decoded.
        var source: Source? = nil
        var complete: Bool? = nil
        var playbackStart: Date? = nil
        var artwork: Data? = nil
        var message: String? = nil
        var connectionActive: Bool? = nil
        var relaySession: String? = nil

        var staleDate: Date? {
            if source == .preview && !playing { return nil }
            return anchorDate.addingTimeInterval(source == .broadcast ? 45 : 12)
        }

        static func waiting(appearance: Appearance) -> Self {
            Self(line: LyricLine("", start: 0, end: 0), next: nil,
                 appearance: appearance, anchorDate: Date(), position: 0,
                 playing: false, waiting: true, repeated: false, revision: 0, source: .capture)
        }

        func time(at date: Date) -> Double {
            position + (playing ? max(0, date.timeIntervalSince(anchorDate)) : 0)
        }

        func date(for lyricTime: Double) -> Date {
            (playbackStart ?? anchorDate.addingTimeInterval(-position)).addingTimeInterval(lyricTime)
        }
    }
    var song: String
}
