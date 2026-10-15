import Foundation

public enum CompactLyrics {
    public static func phrases(_ line: LyricLine) -> [LyricLine] {
        let tokens = StageLayout.tokens(line)
        var groups: [[WordToken]] = []
        var current: [WordToken] = []
        let limit = LyricLanguage.detect(line.text) == .latin ? 8.0 : 3.0
        for token in tokens {
            let width = current.reduce(0) { $0 + $1.units }
            if !current.isEmpty && width + token.units > limit,
               token.start - (current.first?.start ?? 0) >= 0.8 {
                groups.append(current)
                current = []
            }
            current.append(token)
        }
        if !current.isEmpty { groups.append(current) }
        return groups.map { group in
            var words: [LyricWord] = []
            for (index, token) in group.enumerated() {
                if index > 0 && token.space {
                    words.append(LyricWord(" ", start: token.start, end: token.start))
                }
                words += token.letters
            }
            return LyricLine(words.map(\.text).joined(), start: group.first?.start ?? line.start,
                             end: group.last?.end ?? line.end, words: words)
        }
    }

    public static func phrase(_ line: LyricLine, at time: Double) -> LyricLine {
        let parts = phrases(line)
        return parts.last(where: { $0.start <= time }) ?? parts.first ?? line
    }
}
