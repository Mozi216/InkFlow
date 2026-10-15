import XCTest
@testable import InkFlowCore

final class CompactLyricsTests: XCTestCase {
    func testPreviewEndingKeepsItsWholeFinalPhrase() {
        let line = LyricLine("灯光落下，预览到这里", start: 0, end: 5)
        let parts = CompactLyrics.phrases(line)
        XCTAssertEqual(parts.map(\.text), ["灯光落下，", "预览到这里"])
        XCTAssertEqual(CompactLyrics.phrase(line, at: 20).text, "预览到这里")
    }

    func testSingleCharacterTailIsMergedWithoutLosingTimings() {
        let line = LyricLine("一二三四五六七八九", start: 0, end: 9)
        let parts = CompactLyrics.phrases(line)
        XCTAssertFalse(parts.contains { $0.text.count == 1 })
        XCTAssertEqual(parts.flatMap(\.words), line.glyphs)
    }

    func testCameraColumnsKeepAllCharactersAndBalanceWidths() {
        let line = LyricLine("预览到这里", start: 0, end: 5)
        let columns = CompactLyrics.columns(line)
        XCTAssertEqual(columns.map(\.text), ["预览", "到这里"])
        XCTAssertEqual(columns.flatMap(\.words), line.glyphs)
        XCTAssertEqual(CompactLyrics.columns(LyricLine("我", start: 0, end: 1)).map(\.text), ["", "我"])
    }

    func testCameraColumnsDoNotSplitAnEnglishWord() {
        let line = LyricLine("Stay with me", start: 0, end: 3)
        let columns = CompactLyrics.columns(line)
        XCTAssertEqual(columns.map(\.text).joined(separator: " "), line.text)
        XCTAssertEqual(columns.last?.end, line.end)
    }
}
