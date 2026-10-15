import XCTest
@testable import InkFlowCore

final class LyricsTests: XCTestCase {
    func testYRCUsesOriginalAbsoluteWordTimes() {
        let lines = LyricParser.parseYRC("[1000,3000](1000,400,0)风(1400,2600,0)🌙\nmalformed")
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].text, "风🌙")
        XCTAssertEqual(lines[0].words[1].start, 1.4, accuracy: 0.0001)
        XCTAssertEqual(lines[0].words[1].end, 4)
        XCTAssertEqual(lines[0].glyphs.count, 2)
    }

    func testLRCOffsetFractionsAndRepeatedTimestamps() {
        let lines = LyricParser.parseLRC("[offset:-100]\n[00:01.5][00:03.050]light\n[00:04.10]stay", duration: 8)
        XCTAssertEqual(lines.map(\.text), ["light", "light", "stay"])
        XCTAssertEqual(lines[0].start, 1.4, accuracy: 0.0001)
        XCTAssertEqual(lines[1].start, 2.95, accuracy: 0.0001)
        XCTAssertEqual(lines.last?.end, 8)
    }

    func testBreathingGapDoesNotReplaceCurrentLine() {
        let first = LyricLine("first", start: 0, end: 2, words: [LyricWord("first", start: 0, end: 1.5)])
        let next = LyricLine("next", start: 2.5, end: 4)
        let doc = LyricDocument(lines: [first, next], precision: .word)
        XCTAssertEqual(doc.selection(at: 2)?.line, first)
        XCTAssertEqual(doc.selection(at: 2)?.waiting, false)
    }

    func testLongGapPreviewsNextLineWithoutFilling() {
        let doc = LyricDocument(lines: [LyricLine("first", start: 0, end: 1), LyricLine("next", start: 10, end: 12)], precision: .word)
        let selection = doc.selection(at: 5)
        XCTAssertEqual(selection?.line.text, "next")
        XCTAssertEqual(selection?.waiting, true)
        XCTAssertEqual(doc.selection(at: 30)?.line.text, "next")
        XCTAssertEqual(doc.selection(at: 30)?.waiting, false)
    }

    func testPausedClockDoesNotAdvanceAndSeekReanchors() {
        var clock = PlaybackClock()
        clock.duration = 100
        clock.align(position: 10, at: 100, running: true)
        clock.stop(at: 100.5)
        XCTAssertEqual(clock.value(at: 1000), 10.5)
        clock.align(position: 4, at: 1000, running: true)
        XCTAssertEqual(clock.value(at: 1001), 5)
    }

    func testEnglishWordsStayWholeInEveryStyle() {
        let line = LyricLine("We're still here", start: 0, end: 5)
        for style in LyricStyle.allCases {
            let plan = StageLayout.make(line: line, style: style)
            XCTAssertEqual(plan.pages.flatMap { $0 }.map { $0.token.text }, ["We're", "still", "here"], style.rawValue)
            XCTAssertEqual(plan.language, .latin)
        }
    }

    func testEveryCharacterSurvivesLongLinePagination() {
        let line = LyricLine(String(repeating: "风吹过安静的窗", count: 12), start: 0, end: 40)
        for style in LyricStyle.allCases {
            let plan = StageLayout.make(line: line, style: style)
            XCTAssertEqual(plan.pages.flatMap { $0 }.map { $0.token.text }.joined(), line.text)
            XCTAssertGreaterThan(plan.pages.count, 1)
        }
    }

    func testShortPhraseDoesNotExpandToFillTheCanvas() {
        let plan = StageLayout.make(line: LyricLine("stay", start: 0, end: 3), style: .flow)
        XCTAssertLessThanOrEqual(plan.font, 50)
        XCTAssertLessThan(plan.pages[0][0].width, 200)
    }
}
