import Foundation

public enum LyricParser {
    public static func parse(yrc: String?, lrc: String?, duration: Double) -> LyricDocument {
        let words = parseYRC(yrc ?? "")
        if !words.isEmpty { return LyricDocument(lines: words, precision: .word) }
        return LyricDocument(lines: parseLRC(lrc ?? "", duration: duration), precision: .line)
    }

    public static func parseYRC(_ text: String) -> [LyricLine] {
        let header = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
        let mark = try! NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)"#)
        return text.components(separatedBy: .newlines).compactMap { raw in
            let string = raw as NSString
            guard let h = header.firstMatch(in: raw, range: NSRange(location: 0, length: string.length)),
                  let start = Double(string.substring(with: h.range(at: 1))),
                  let length = Double(string.substring(with: h.range(at: 2))) else { return nil }
            let matches = mark.matches(in: raw, range: NSRange(location: h.range.length,
                                                               length: string.length - h.range.length))
            let words = matches.enumerated().compactMap { index, match -> LyricWord? in
                guard let at = Double(string.substring(with: match.range(at: 1))),
                      let span = Double(string.substring(with: match.range(at: 2))) else { return nil }
                let from = NSMaxRange(match.range)
                let to = index + 1 < matches.count ? matches[index + 1].range.location : string.length
                return LyricWord(string.substring(with: NSRange(location: from, length: to - from)),
                                 start: at / 1000, end: (at + span) / 1000)
            }
            guard !words.isEmpty else { return nil }
            return LyricLine(words.map(\.text).joined(), start: start / 1000,
                             end: (start + length) / 1000, words: words)
        }.sorted { $0.start < $1.start }
    }

    public static func parseLRC(_ text: String, duration: Double) -> [LyricLine] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let source = text as NSString
        let offsetMatch = offsetPattern.firstMatch(in: text, range: NSRange(location: 0, length: source.length))
        let offset = offsetMatch.flatMap { Double(source.substring(with: $0.range(at: 1))) } ?? 0
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let string = raw as NSString
            let matches = stamp.matches(in: raw, range: NSRange(location: 0, length: string.length))
            guard let last = matches.last else { continue }
            let lyric = string.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(string.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(string.substring(with: match.range(at: 2))) ?? 0
                let fraction = match.range(at: 3).location == NSNotFound ? "0" : string.substring(with: match.range(at: 3))
                let start = max(0, minutes * 60 + seconds + (Double("0." + fraction) ?? 0) + offset / 1000)
                lines.append(LyricLine(lyric, start: start, end: start))
            }
        }
        lines.sort { $0.start < $1.start }
        for index in lines.indices {
            let fallbackEnd = duration > lines[index].start ? duration : lines[index].start + 5
            lines[index].end = max(lines[index].start,
                index + 1 < lines.count ? lines[index + 1].start : fallbackEnd)
        }
        return lines
    }
}
