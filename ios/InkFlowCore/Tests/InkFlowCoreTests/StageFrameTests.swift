import XCTest
@testable import InkFlowCore

final class StageFrameTests: XCTestCase {
    private func snapshot(_ line: LyricLine, position: Double, waiting: Bool = false) -> LyricSnapshot {
        LyricSnapshot(line: line, next: LyricLine("下一句", start: 9, end: 12), appearance: Appearance(),
            anchorDate: Date(timeIntervalSince1970: 100), position: position, playing: true,
            waiting: waiting, repeated: false, revision: 3,
            playbackStart: Date(timeIntervalSince1970: 90))
    }

    func testCinemaRetainsItsCompleteMotion() {
        let plan = StageLayout.make(line: LyricLine("Stay with me", start: 0, end: 8), style: .cinema)
        let early = StageFrame(plan: plan, state: snapshot(plan.line, position: 1))
        let late = StageFrame(plan: plan, state: snapshot(plan.line, position: 6))
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
        let before = StageFrame(plan: plan, state: snapshot(line, position: 4, waiting: true))
        let delayed = StageFrame(plan: plan, state: snapshot(line, position: 29, waiting: true))
        XCTAssertEqual(before.page, 0)
        XCTAssertEqual(delayed.page, 0)
        XCTAssertEqual(before.poses.map(\.id), delayed.poses.map(\.id))
        XCTAssertTrue(delayed.poses.allSatisfy { $0.fill == 0 && $0.blur == 0 })
        XCTAssertNotEqual(before.ambient.rotation, delayed.ambient.rotation)
    }

    func testPublishedSceneSurvivesSerializationWithoutChangingComposition() throws {
        for text in ["让风穿过安静的窗", "Let the light stay with us", "光と影を重ねて"] {
            for style in LyricStyle.allCases {
                var sent = snapshot(LyricLine(text, start: 0, end: 8), position: 3.3)
                sent.appearance.style = style
                sent.appearance.theme = "rose"
                sent.appearance.glow = 1.4
                sent.appearance.rows = 1
                let received = try JSONDecoder().decode(LyricSnapshot.self, from: JSONEncoder().encode(sent))
                XCTAssertEqual(sent, received)
                let appPlan = StageLayout.make(line: sent.line, style: sent.appearance.style, rows: sent.appearance.rows)
                let islandPlan = StageLayout.make(line: received.line, style: received.appearance.style, rows: received.appearance.rows)
                let first = StageFrame(plan: appPlan, state: sent)
                let second = StageFrame(plan: islandPlan, state: received)
                XCTAssertEqual(first.page, second.page)
                XCTAssertEqual(first.poses.map(\.token), second.poses.map(\.token))
                XCTAssertEqual(first.poses.map(\.x), second.poses.map(\.x))
                XCTAssertEqual(first.poses.map(\.fill), second.poses.map(\.fill))
                XCTAssertEqual(first.ambient.rotation, second.ambient.rotation)
                XCTAssertEqual(sent.date(for: 4), received.date(for: 4))
            }
        }
    }

    func testReducedMotionStillFillsLyrics() {
        let plan = StageLayout.make(line: LyricLine("光と影", start: 0, end: 8), style: .scatter)
        let early = StageFrame(plan: plan, state: snapshot(plan.line, position: 1), reduced: true)
        let late = StageFrame(plan: plan, state: snapshot(plan.line, position: 7), reduced: true)
        XCTAssertEqual(late.ambient.rotation, 0)
        XCTAssertEqual(late.ambient.scale, 1)
        XCTAssertTrue(late.poses.allSatisfy { $0.rotation == 0 && $0.blur == 0 })
        XCTAssertGreaterThan(late.poses.reduce(0) { $0 + $1.fill }, early.poses.reduce(0) { $0 + $1.fill })
    }

    func testUnrelatedUpdatesCannotChangeFrozenSceneOrFillOrigin() {
        var state = snapshot(LyricLine("Stay with me", start: 0, end: 8), position: 3.3)
        state.playing = false
        let plan = StageLayout.make(line: state.line, style: .cinema)
        let before = StageFrame(plan: plan, state: state)
        let fillOrigin = state.date(for: 4)
        state.revision += 100
        state.anchorDate = state.anchorDate.addingTimeInterval(60)
        let later = StageFrame(plan: plan, state: state)
        XCTAssertEqual(before.poses.map(\.x), later.poses.map(\.x))
        XCTAssertEqual(before.poses.map(\.fill), later.poses.map(\.fill))
        XCTAssertEqual(before.ambient.rotation, later.ambient.rotation)
        XCTAssertEqual(fillOrigin, state.date(for: 4))
        XCTAssertEqual(state.time(at: Date(timeIntervalSince1970: 10000)), 3.3)
    }
}
