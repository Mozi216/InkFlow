import Foundation

public struct LyricWord: Codable, Hashable, Sendable {
    enum CodingKeys: String, CodingKey { case text = "t", start = "s", end = "e" }
    public var text: String
    public var start: Double
    public var end: Double

    public init(_ text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = max(start, end)
    }
}

public struct LyricLine: Codable, Hashable, Sendable, Identifiable {
    public var text: String
    public var start: Double
    public var end: Double
    public var words: [LyricWord]
    public var id: String { "\(start):\(text)" }

    public init(_ text: String, start: Double, end: Double, words: [LyricWord] = []) {
        self.text = text
        self.start = start
        self.end = max(start, end)
        self.words = words
    }

    public var vocalEnd: Double {
        guard let last = words.map(\.end).max() else { return end }
        return min(end, last)
    }

    public var glyphs: [LyricWord] {
        // LRC 只能估计填充；保留来源精度，不能把估计标成逐字歌词。
        let source = words.isEmpty ? [LyricWord(text, start: start, end: end)] : words
        return source.flatMap { word in
            let letters = Array(word.text).map(String.init)
            return letters.enumerated().map { index, text in
                let step = (word.end - word.start) / Double(max(1, letters.count))
                return LyricWord(text, start: word.start + step * Double(index),
                                 end: word.start + step * Double(index + 1))
            }
        }
    }
}

public struct LyricDocument: Codable, Hashable, Sendable {
    public enum Precision: String, Codable, Sendable { case word, line }
    public var lines: [LyricLine]
    public var precision: Precision

    public init(lines: [LyricLine], precision: Precision) {
        self.lines = lines.sorted { $0.start < $1.start }
        self.precision = precision
    }

    public func selection(at time: Double) -> LyricSelection? {
        let vocals = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = vocals.first else { return nil }
        guard let index = vocals.lastIndex(where: { $0.start <= time }) else {
            return LyricSelection(line: first, next: nil, waiting: true)
        }
        let line = vocals[index]
        let next = index + 1 < vocals.count ? vocals[index + 1] : nil
        // 三秒以内的换气保留当前句；最后一句一直留下。
        if let next, time >= line.vocalEnd, next.start - line.vocalEnd >= 3 {
            return LyricSelection(line: next, next: nil, waiting: true)
        }
        return LyricSelection(line: line, next: next, waiting: false)
    }
}

public struct LyricSelection: Equatable, Sendable {
    public var line: LyricLine
    public var next: LyricLine?
    public var waiting: Bool
}

public func clamped(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
    min(max(value, lower), max(lower, upper))
}

public func fillProgress(at time: Double, start: Double, end: Double) -> Double {
    if end <= start { return time >= start ? 1 : 0 }
    return clamped((time - start) / (end - start))
}
