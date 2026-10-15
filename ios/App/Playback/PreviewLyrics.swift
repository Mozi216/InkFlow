import InkFlowCore

enum PreviewLyrics {
    static let duration = 40.0
    static let islandDuration = 20.0
    // 自写测试文案。首尾不同，便于区分结束和卡住。
    static let document: LyricDocument = {
        let samples: [(String, Double, Double)] = [
            ("让风穿过安静的窗", 1, 6),
            ("Let the light stay with us", 6.8, 12),
            ("光と影を重ねて", 13, 20),
            ("把这一刻，轻轻留下！", 26, 31),
            ("灯光落下，预览到这里", 32, 38)
        ]
        return LyricDocument(lines: samples.map { text, start, end in
            let chars = Array(text).map(String.init)
            let step = (end - start) / Double(chars.count)
            return LyricLine(text, start: start, end: end, words: chars.enumerated().map { i, c in
                LyricWord(c, start: start + Double(i) * step, end: start + Double(i + 1) * step)
            })
        }, precision: .word)
    }()

    static let islandDocument = LyricDocument(lines: document.lines.map { line in
        LyricLine(line.text, start: line.start / 2, end: line.end / 2, words: line.words.map {
            LyricWord($0.text, start: $0.start / 2, end: $0.end / 2)
        })
    }, precision: .word)
}
