import Foundation

public struct RecognitionCandidate: Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var artist: String
    public var artistIDs: [Int64]
    public var duration: Double
    public var position: Double

    public init(id: Int64, title: String, artist: String, artistIDs: [Int64] = [],
                duration: Double, position: Double) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artistIDs = artistIDs
        self.duration = duration
        self.position = position
    }

    func sameRecording(as other: Self) -> Bool {
        let artistsMatch = !artistIDs.isEmpty && !other.artistIDs.isEmpty
            ? artistIDs.sorted() == other.artistIDs.sorted()
            : key(artist) == key(other.artist)
        return !key(title).isEmpty && !key(artist).isEmpty && artistsMatch
            && key(title) == key(other.title) && abs(duration - other.duration) <= 1
    }

    private func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Recognition is evidence, not a player event. Conflicting recordings must not pick a winner.
public struct RecognitionTracker {
    public enum Decision: Equatable {
        case accepted(RecognitionCandidate), confirming, ambiguous, unmatched, outdated
    }
    private struct Observation {
        var candidate: RecognitionCandidate
        var start: Double
        var end: Double
    }
    private var confirmed: Observation?
    private var pending: Observation?
    private var lastWindowEnd = -Double.infinity
    public var confirmedID: Int64? { confirmed?.candidate.id }

    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func expire(at now: Double) -> Bool {
        guard let confirmed, now - confirmed.end > 8 else { return false }
        self.confirmed = nil
        return true
    }

    public mutating func observe(_ candidates: [RecognitionCandidate], start: Double,
                                 duration: Double, now: Double) -> Decision {
        let end = start + duration
        guard start.isFinite, duration.isFinite, duration > 0, now.isFinite,
              end <= now + 0.5, now - end <= 4, end > lastWindowEnd else { return .outdated }
        lastWindowEnd = end
        let valid = candidates.filter {
            $0.id > 0 && $0.duration.isFinite && $0.duration > 0 && $0.position.isFinite
                && $0.position >= 0 && $0.position + duration <= $0.duration + 1
        }
        guard let first = valid.first else {
            pending = nil
            return .unmatched
        }
        guard valid.allSatisfy({ first.sameRecording(as: $0) && abs(first.position - $0.position) <= 0.75 }) else {
            confirmed = nil
            pending = nil
            return .ambiguous
        }
        // Only equivalent catalogue editions may retain their previous ID.
        let chosen = valid.first(where: { $0.id == confirmed?.candidate.id }) ?? first
        let next = Observation(candidate: chosen, start: start, end: end)
        if let confirmed, now - confirmed.end <= 8, continuous(confirmed, next) {
            self.confirmed = next
            pending = nil
            return .accepted(chosen)
        }
        if let pending, end - pending.end >= 1.5, end - pending.end <= 6, continuous(pending, next) {
            confirmed = next
            self.pending = nil
            return .accepted(chosen)
        }
        confirmed = nil
        pending = next
        return .confirming
    }

    private func continuous(_ before: Observation, _ after: Observation) -> Bool {
        before.candidate.sameRecording(as: after.candidate)
            && abs((after.candidate.position - before.candidate.position) - (after.start - before.start)) <= 0.75
    }
}
