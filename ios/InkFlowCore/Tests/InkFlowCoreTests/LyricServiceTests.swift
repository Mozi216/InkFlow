import XCTest
@testable import InkFlowCore

final class LyricServiceTests: XCTestCase {
    func testEmptyResponseIsNotInstrumental() {
        XCTAssertEqual(LyricServiceResult(yrc: nil, lrc: nil, pureMusic: false, duration: 100).availability, .unavailable)
    }

    func testPlaceholderIsNotRenderedAsASongLyric() {
        let response = LyricServiceResult(yrc: nil, lrc: "[00:05.00]纯音乐，请欣赏", pureMusic: true, duration: 95)
        XCTAssertEqual(response.availability, .instrumental)
        XCTAssertTrue(response.document.lines.isEmpty)
    }

    func testPlaceholderWithoutExplicitFlagDoesNotProveInstrumental() {
        XCTAssertEqual(LyricServiceResult(yrc: nil, lrc: "[00:05.00]纯音乐，请欣赏", pureMusic: false,
                                         duration: 95).availability, .unavailable)
    }

    func testRealLyricsOverrideStaleInstrumentalFlag() {
        let response = LyricServiceResult(yrc: "", lrc: "{\"t\":0,\"c\":[{\"tx\":\"作曲\"}]}\n[00:14.47]第一句\n[00:18.70]第二句",
                                         pureMusic: true, duration: 122.207)
        XCTAssertEqual(response.availability, .available)
        XCTAssertEqual(response.document.lines.count, 2)
        XCTAssertEqual(response.document.lines[0].start, 14.47, accuracy: 0.001)
    }
}
