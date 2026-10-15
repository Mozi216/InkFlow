import InkFlowCore

enum PreviewLyrics {
    // 自写测试文案，包含长音、换气、长间奏、重复句及英文整词。
    static let document: LyricDocument = {
        let samples: [(String, Double, Double)] = [
            ("让风穿过安静的窗", 1, 6),
            ("Let the light stay with us", 6.8, 12),
            ("光と影を重ねて", 13, 20),
            ("把这一刻，轻轻留下！", 26, 31),
            ("让风穿过安静的窗", 32, 38)
        ]
        return LyricDocument(lines: samples.map { text, start, end in
            let chars = Array(text).map(String.init)
            let step = (end - start) / Double(chars.count)
            return LyricLine(text, start: start, end: end, words: chars.enumerated().map { i, c in
                LyricWord(c, start: start + Double(i) * step, end: start + Double(i + 1) * step)
            })
        }, precision: .word)
    }()
}
