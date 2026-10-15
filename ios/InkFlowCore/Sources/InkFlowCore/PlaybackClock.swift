import Foundation

public struct PlaybackClock: Sendable {
    public private(set) var position = 0.0
    public private(set) var anchor = 0.0
    public private(set) var running = false
    public var duration = 0.0

    public init() {}

    public func value(at uptime: Double) -> Double {
        let value = position + (running ? max(0, uptime - anchor) : 0)
        return clamped(value, 0, duration > 0 ? duration : .greatestFiniteMagnitude)
    }

    public func hasFinished(at uptime: Double) -> Bool {
        duration > 0 && value(at: uptime) >= duration
    }

    public mutating func align(position: Double, at uptime: Double, running: Bool) {
        guard position.isFinite, uptime.isFinite else { return }
        self.position = max(0, position)
        anchor = uptime
        self.running = running
    }

    public mutating func stop(at uptime: Double) {
        position = value(at: uptime)
        anchor = uptime
        running = false
    }

    public mutating func followAudio(position: Double, observedAt: Double, lastSound: Double, now: Double) {
        let audible = now - lastSound < 1.5
        // A late recognition result must not restart the clock after audio has stopped.
        let heardPosition = audible ? position : max(0, position + lastSound - observedAt)
        let heardNow = audible ? heardPosition + max(0, now - observedAt) : heardPosition
        // Recognition jitter must not rebuild every system timer mask.
        if running == audible && abs(heardNow - value(at: now)) < 0.18 { return }
        align(position: heardPosition, at: audible ? observedAt : now, running: audible)
    }
}
