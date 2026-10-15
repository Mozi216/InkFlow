import XCTest
@testable import InkFlowCore

final class MotionParityTests: XCTestCase {
    struct Reference: Decodable {
        var label: String
        var plan: StagePlan
        var time: Double
        var reduced: Bool
        var expected: [Expected]
    }
    struct Expected: Decodable {
        var index: Int
        var x, y, scale, rotation, opacity, blur, fill: Double
    }

    func testMotionMatchesWindowsReference() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "motion", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
        XCTAssertEqual(cases.count, 72)
        for reference in cases {
            let actual = StageMotion.poses(reference.plan, at: reference.time, reduced: reference.reduced)
            XCTAssertEqual(actual.count, reference.expected.count, reference.label)
            for (pose, expected) in zip(actual, reference.expected) {
                XCTAssertEqual(pose.id, expected.index, reference.label)
                XCTAssertEqual(pose.x, expected.x, accuracy: 0.00001, reference.label)
                XCTAssertEqual(pose.y, expected.y, accuracy: 0.00001, reference.label)
                XCTAssertEqual(pose.scale, expected.scale, accuracy: 0.00001, reference.label)
                XCTAssertEqual(pose.rotation, expected.rotation, accuracy: 0.00001, reference.label)
                XCTAssertEqual(pose.opacity, expected.opacity, accuracy: 0.00001, reference.label)
                XCTAssertEqual(pose.blur, expected.blur, accuracy: 0.00001, reference.label)
                XCTAssertEqual(pose.fill, expected.fill, accuracy: 0.00001, reference.label)
            }
        }
    }

    func testAmbientMotionContinuesAfterVocalEndAndCanFreeze() {
        let first = StageMotion.ambient(.cinema, at: 8)
        let later = StageMotion.ambient(.cinema, at: 10)
        XCTAssertNotEqual(first.x, later.x)
        XCTAssertEqual(StageMotion.ambient(.cinema, at: 8).x, first.x)
        XCTAssertEqual(StageMotion.ambient(.cinema, at: 8, reduced: true).scale, 1)
    }

    func testCinemaSwingsBothWaysWithoutSuddenJumps() {
        let samples = (0...600).map { StageMotion.ambient(.cinema, at: Double($0) / 60) }
        // The base lettering is tilted -2 degrees; the complete scene crosses zero.
        XCTAssertLessThan(samples.map { $0.rotation - 2 }.min()!, -3)
        XCTAssertGreaterThan(samples.map { $0.rotation - 2 }.max()!, 3)
        for (a, b) in zip(samples, samples.dropFirst()) {
            XCTAssertLessThan(abs(a.rotation - b.rotation), 0.1)
            XCTAssertLessThan(abs(a.x - b.x), 0.11)
        }
    }

    func testEveryStyleKeepsMovingButRespectsReducedMotion() {
        for style in [LyricStyle.flow, .columns, .scatter, .collage, .cinema] {
            let a = StageMotion.ambient(style, at: 20)
            let b = StageMotion.ambient(style, at: 22)
            XCTAssertNotEqual(a.y, b.y)
            let still = StageMotion.ambient(style, at: 20, reduced: true)
            XCTAssertEqual(still.x, 0)
            XCTAssertEqual(still.y, 0)
            XCTAssertEqual(still.rotation, 0)
            XCTAssertEqual(still.scale, 1)
        }
    }
}
