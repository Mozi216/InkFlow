import Foundation

public enum CompactLyrics {
    public static func phrases(_ line: LyricLine) -> [LyricLine] {
        let tokens = StageLayout.tokens(line)
        var groups: [[WordToken]] = []
        var current: [WordToken] = []
        let limit = LyricLanguage.detect(line.text) == .latin ? 12.0 : 8.0
        for token in tokens {
            let width = current.reduce(0) { $0 + $1.units }
            let punctuation = current.last?.text.last.map { "，。！？；、,!?;".contains($0) } ?? false
            if !current.isEmpty && (width + token.units > limit || (punctuation && width >= 2)),
               token.start - (current.first?.start ?? 0) >= 0.8 {
                groups.append(current)
                current = []
            }
            current.append(token)
        }
        if !current.isEmpty { groups.append(current) }
        // A short tail belongs to the preceding phrase, never a page of its own.
        if groups.count > 1, let tail = groups.last, tail.reduce(0, { $0 + $1.units }) < 2 {
            groups.removeLast()
            groups[groups.count - 1] += tail
        }
        return groups.map(makeLine)
    }

    public static func phrase(_ line: LyricLine, at time: Double) -> LyricLine {
        let parts = phrases(line)
        return parts.last(where: { $0.start <= time }) ?? parts.first ?? line
    }

    /// Balance two short rows for the minimal presentation, keeping words intact.
    public static func columns(_ phrase: LyricLine) -> [LyricLine] {
        let tokens = StageLayout.tokens(phrase)
        guard tokens.count > 1 else { return [makeLine([]), phrase] }
        let total = tokens.reduce(0) { $0 + $1.units }
        var left = 0.0, best = 1, distance = Double.infinity
        for index in 1..<tokens.count {
            left += tokens[index - 1].units
            let difference = abs(total - 2 * left)
            if difference < distance { best = index; distance = difference }
        }
        return [makeLine(Array(tokens[..<best])), makeLine(Array(tokens[best...]))]
    }

    private static func makeLine(_ group: [WordToken]) -> LyricLine {
        var words: [LyricWord] = []
        for (index, token) in group.enumerated() {
            if index > 0 && token.space {
                words.append(LyricWord(" ", start: token.start, end: token.start))
            }
            words += token.letters
        }
        return LyricLine(words.map(\.text).joined(), start: group.first?.start ?? 0,
                         end: group.last?.end ?? 0, words: words)
    }
}
