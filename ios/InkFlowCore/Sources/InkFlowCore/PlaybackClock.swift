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
}
