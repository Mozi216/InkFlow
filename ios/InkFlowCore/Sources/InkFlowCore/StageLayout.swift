import Foundation

public struct WordToken: Codable, Hashable, Sendable {
    public var text: String
    public var letters: [LyricWord]
    public var widths: [Double]
    public var units: Double
    public var space: Bool
    public var start: Double { letters.first?.start ?? 0 }
    public var end: Double { letters.last?.end ?? start }
}

public struct PlacedToken: Codable, Hashable, Sendable, Identifiable {
    public var token: WordToken
    public var x: Double
    public var y: Double
    public var font: Double
    public var width: Double
    public var row: Int
    public var index: Int
    public var id: Int { index }
}

public struct StagePlan: Codable, Sendable {
    public var line: LyricLine
    public var style: LyricStyle
    public var language: LyricLanguage
    public var pages: [[PlacedToken]]
    public var width: Double
    public var height: Double
    public var font: Double
}

public enum StageLayout {
    public static func fallbackWidth(_ text: String) -> Double {
        text.reduce(0) { total, char in
            if char.unicodeScalars.contains(where: LyricLanguage.isCJK) { return total + 1 }
            if "ilI.,'!|".contains(char) { return total + 0.25 }
            if "mwMW".contains(char) { return total + 0.85 }
            if char.isWhitespace { return total + 0.28 }
            return total + 0.53
        }
    }

    public static func tokens(_ line: LyricLine, segments: [String]? = nil,
                              measure: (String) -> Double = fallbackWidth) -> [WordToken] {
        let letters = line.glyphs
        var groups: [[LyricWord]] = []
        if let segments, segments.joined() == letters.map(\.text).joined() {
            var cursor = 0
            for part in segments {
                let count = part.count
                groups.append(Array(letters[cursor..<(cursor + count)]))
                cursor += count
            }
        } else {
            var word: [LyricWord] = []
            for letter in letters {
                let cjk = letter.text.unicodeScalars.contains(where: LyricLanguage.isCJK)
                let space = letter.text.allSatisfy(\.isWhitespace)
                if cjk || space {
                    if !word.isEmpty { groups.append(word); word = [] }
                    groups.append([letter])
                } else { word.append(letter) }
            }
            if !word.isEmpty { groups.append(word) }
        }
        var result: [WordToken] = []
        var space = false
        for group in groups {
            let text = group.map(\.text).joined()
            if text.allSatisfy(\.isWhitespace) { space = true; continue }
            result.append(WordToken(text: text, letters: group,
                widths: group.map { measure($0.text) }, units: max(0.2, measure(text)), space: space))
            space = false
        }
        return result
    }

    public static func make(line: LyricLine, width: Double = 740, height: Double = 280,
                            fontLimit: Double = 50, style: LyricStyle, repeated: Bool = false,
                            rows: Int = 2, segments: [String]? = nil,
                            measure: (String) -> Double = fallbackWidth) -> StagePlan {
        let mode = style.resolved(for: line, repeated: repeated)
        let language = LyricLanguage.detect(line.text)
        var words = tokens(line, segments: segments, measure: measure)
        let maxToken = max(1, words.map(\.units).max() ?? 1)
        let font = max(14, min(fontLimit, (width - 104) / (maxToken * 1.08), (height - 116) / 2.9))
        var pages: [[PlacedToken]] = []

        if mode == .columns && language != .latin {
            words = words.flatMap { word in
                word.letters.map { WordToken(text: $0.text, letters: [$0], widths: [1], units: 1, space: false) }
            }
            let f = min(fontLimit, (height - 110) / 3.7)
            let rowCount = min(3, max(1, Int((height - 110) / (f * 1.25))))
            let columns = min(7, max(1, Int((width - 120) / (f * 1.8))))
            for start in stride(from: 0, to: words.count, by: rowCount * columns) {
                let group = Array(words[start..<min(words.count, start + rowCount * columns)])
                let count = Int(ceil(Double(group.count) / Double(rowCount)))
                pages.append(group.enumerated().map { i, word in
                    let column = i / rowCount
                    let size = f * [1, 0.96, 1.03, 0.98][column % 4]
                    return PlacedToken(token: word,
                        x: width / 2 + (Double(count) / 2 - 0.5 - Double(column)) * f * 1.25,
                        y: 42 + size * 0.75 + Double(i % rowCount) * f * 1.25 + [0, 0.32, 0.12, 0.48][column % 4] * f,
                        font: size, width: size, row: i % rowCount, index: start + i)
                })
            }
        } else {
            let seed = line.text.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            let scattered = mode == .scatter
            if scattered && language == .cjk {
                words = words.flatMap { word in
                    word.letters.map { WordToken(text: $0.text, letters: [$0], widths: [1], units: 1, space: false) }
                }
            }
            let capacity = scattered ? (height < 240 ? 1 : 2) : max(1, min(rows, Int((height - 116) / (font * 1.55))))
            let total = words.reduce(0) { $0 + $1.units + ($1.space ? 0.28 : 0) }
            let available = max(100, width - 104)
            let balanced = font * max(5, min(available / font,
                total / Double(max(1, min(capacity, Int(ceil(total * font / available)))))))
            let rowWidth = scattered ? min(width - 120, font * (language == .latin ? 16 : 12)) : min(available, balanced)
            var grouped: [[PlacedToken]] = []
            var group: [PlacedToken] = []
            var used = 0.0
            for (index, word) in words.enumerated() {
                let factor = scattered ? [1.12, 0.84, 1, 0.92, 1.06][(index + seed) % 5] : 1
                let size = font * factor
                let gap = group.isEmpty ? 0 : font * (word.space ? (scattered ? 0.3 : 0.28) : (scattered ? 0.1 : 0))
                if !group.isEmpty && used + size * word.units + gap > rowWidth {
                    grouped.append(group); group = []; used = 0
                }
                let advance = group.isEmpty ? 0 : gap
                group.append(PlacedToken(token: word, x: used + advance + size * word.units / 2,
                                         y: 0, font: size, width: size * word.units, row: 0, index: index))
                used += advance + size * word.units
            }
            if !group.isEmpty { grouped.append(group) }
            for start in stride(from: 0, to: grouped.count, by: capacity) {
                var page: [PlacedToken] = []
                for (row, group) in grouped[start..<min(grouped.count, start + capacity)].enumerated() {
                    let length = group.last.map { $0.x + $0.width / 2 } ?? 0
                    page += group.map { item in
                        var token = item
                        token.x += (width - length) / 2
                        token.row = row
                        let stagger = [0, 0.28, -0.1, 0.15][(token.index + seed) % 4] * font
                        token.y = scattered ? 48 + font * 0.85 + Double(row) * font * 1.65 + stagger
                            : 42 + token.font * 0.75 + Double(row) * token.font * 1.3
                        return token
                    }
                }
                pages.append(page)
            }
        }
        return StagePlan(line: line, style: mode, language: language, pages: pages,
                         width: width, height: height, font: font)
    }
}
