import XCTest
@testable import InkFlowCore

final class StageFrameTests: XCTestCase {
    func testCinemaRetainsItsCompleteMotion() {
        let plan = StageLayout.make(line: LyricLine("Stay with me", start: 0, end: 8), style: .cinema)
        let early = StageFrame(plan: plan, position: 1, waiting: false)
        let late = StageFrame(plan: plan, position: 6, waiting: false)
        XCTAssertEqual(early.poses.map(\.id), late.poses.map(\.id))
        XCTAssertNotEqual(early.poses.map(\.x), late.poses.map(\.x))
        XCTAssertNotEqual(early.poses.map(\.scale), late.poses.map(\.scale))
        XCTAssertNotEqual(early.ambient.rotation, late.ambient.rotation)
        XCTAssertGreaterThan(late.poses.reduce(0) { $0 + $1.fill }, early.poses.reduce(0) { $0 + $1.fill })
    }

    func testWaitingDoesNotRevealOrPageAhead() {
        let line = LyricLine(String(repeating: "光と影を重ねて", count: 5), start: 10, end: 30)
        let plan = StageLayout.make(line: line, style: .columns)
        XCTAssertGreaterThan(plan.pages.count, 1)
        let before = StageFrame(plan: plan, position: 4, waiting: true)
        let delayed = StageFrame(plan: plan, position: 29, waiting: true)
        XCTAssertEqual(before.page, 0)
        XCTAssertEqual(delayed.page, 0)
        XCTAssertEqual(before.poses.map(\.id), delayed.poses.map(\.id))
        XCTAssertTrue(delayed.poses.allSatisfy { $0.fill == 0 && $0.blur == 0 })
        XCTAssertEqual(before.ambient.rotation, delayed.ambient.rotation)
    }

    func testPublishedSceneSurvivesSerializationWithoutChangingComposition() throws {
        for text in ["让风穿过安静的窗", "Let the light stay with us", "光と影を重ねて"] {
            for style in LyricStyle.allCases {
                let plan = StageLayout.make(line: LyricLine(text, start: 0, end: 8), style: style)
                let decoded = try JSONDecoder().decode(StagePlan.self, from: JSONEncoder().encode(plan))
                let first = StageFrame(plan: plan, position: 3.3, waiting: false)
                let second = StageFrame(plan: decoded, position: 3.3, waiting: false)
                XCTAssertEqual(first.page, second.page)
                XCTAssertEqual(first.poses.map(\.token), second.poses.map(\.token))
                XCTAssertEqual(first.poses.map(\.x), second.poses.map(\.x))
                XCTAssertEqual(first.poses.map(\.fill), second.poses.map(\.fill))
                XCTAssertEqual(first.ambient.rotation, second.ambient.rotation)
            }
        }
    }

    func testReducedMotionStillFillsLyrics() {
        let plan = StageLayout.make(line: LyricLine("光と影", start: 0, end: 8), style: .scatter)
        let early = StageFrame(plan: plan, position: 1, waiting: false, reduced: true)
        let late = StageFrame(plan: plan, position: 7, waiting: false, reduced: true)
        XCTAssertEqual(late.ambient.rotation, 0)
        XCTAssertEqual(late.ambient.scale, 1)
        XCTAssertTrue(late.poses.allSatisfy { $0.rotation == 0 && $0.blur == 0 })
        XCTAssertGreaterThan(late.poses.reduce(0) { $0 + $1.fill }, early.poses.reduce(0) { $0 + $1.fill })
    }
}
