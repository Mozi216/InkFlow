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
}
