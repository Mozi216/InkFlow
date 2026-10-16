import Foundation

public enum LyricSource: String, Codable, Sendable {
    case preview, capture, broadcast
}

/// The same value drives the app preview and crosses the ActivityKit boundary.
public struct LyricSnapshot: Codable, Hashable, Sendable {
    public var line: LyricLine
    public var next: LyricLine?
    public var appearance: Appearance
    public var anchorDate: Date
    public var position: Double
    public var playing: Bool
    public var waiting: Bool
    public var repeated: Bool
    public var revision: Int
    public var source: LyricSource?
    public var complete: Bool?
    public var playbackStart: Date?
    public var artwork: Data?
    public var message: String?
    public var connectionActive: Bool?
    public var relaySession: String?

    public init(line: LyricLine, next: LyricLine?, appearance: Appearance, anchorDate: Date,
                position: Double, playing: Bool, waiting: Bool, repeated: Bool, revision: Int,
                source: LyricSource? = nil, complete: Bool? = nil, playbackStart: Date? = nil,
                artwork: Data? = nil, message: String? = nil, connectionActive: Bool? = nil,
                relaySession: String? = nil) {
        self.line = line
        self.next = next
        self.appearance = appearance
        self.anchorDate = anchorDate
        self.position = position
        self.playing = playing
        self.waiting = waiting
        self.repeated = repeated
        self.revision = revision
        self.source = source
        self.complete = complete
        self.playbackStart = playbackStart
        self.artwork = artwork
        self.message = message
        self.connectionActive = connectionActive
        self.relaySession = relaySession
    }

    public var staleDate: Date? {
        if source == .preview && !playing { return nil }
        return anchorDate.addingTimeInterval(source == .broadcast ? 45 : 12)
    }

    public static func waiting(appearance: Appearance) -> Self {
        Self(line: LyricLine("", start: 0, end: 0), next: nil, appearance: appearance,
             anchorDate: Date(), position: 0, playing: false, waiting: true,
             repeated: false, revision: 0, source: .capture)
    }

    public func time(at date: Date) -> Double {
        position + (playing ? max(0, date.timeIntervalSince(anchorDate)) : 0)
    }

    public func date(for lyricTime: Double) -> Date {
        (playbackStart ?? anchorDate.addingTimeInterval(-position)).addingTimeInterval(lyricTime)
    }
}
