import Foundation

/// Keep timer ranges unchanged until playback is actually paused, sought or corrected.
public struct PlaybackDates {
    public private(set) var start = Date.distantPast
    private var anchor: Double?
    private var position = 0.0
    private var running = false
    private var calibration = 0.0

    public init() {}

    public mutating func update(_ clock: PlaybackClock, at uptime: Double, date: Date,
                                calibration: Double = 0) {
        guard anchor != clock.anchor || position != clock.position || running != clock.running
                || self.calibration != calibration else { return }
        anchor = clock.anchor
        position = clock.position
        running = clock.running
        self.calibration = calibration
        let elapsed = clock.running ? uptime - clock.anchor : 0
        start = date.addingTimeInterval(-clock.position - elapsed - calibration)
    }
}
