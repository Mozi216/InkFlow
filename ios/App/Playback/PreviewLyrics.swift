import InkFlowCore

enum PreviewLyrics {
    static let duration = 20.0
    // 自写测试文案。首尾不同，便于区分结束和卡住。
    static let document: LyricDocument = {
        let samples: [(String, Double, Double)] = [
            ("让风穿过安静的窗", 0.5, 3),
            ("Let the light stay with us", 3.4, 6),
            ("光と影を重ねて", 6.5, 10),
            ("把这一刻，轻轻留下！", 13, 15.5),
            ("灯光落下，预览到这里", 16, 19)
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
