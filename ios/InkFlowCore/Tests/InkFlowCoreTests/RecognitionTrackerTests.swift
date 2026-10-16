import XCTest
@testable import InkFlowCore

final class RecognitionTrackerTests: XCTestCase {
    private func song(_ id: Int64 = 1, title: String = "Again", artist: String = "王极",
                      at position: Double = 20, duration: Double = 122) -> RecognitionCandidate {
        RecognitionCandidate(id: id, title: title, artist: artist, duration: duration, position: position)
    }

    func testFirstHitNeedsASecondAdvancingWindow() {
        var tracker = RecognitionTracker()
        XCTAssertEqual(tracker.observe([song()], start: 100, duration: 6, now: 106.3), .confirming)
        XCTAssertEqual(tracker.observe([song(at: 22)], start: 102, duration: 6, now: 108.4), .accepted(song(at: 22)))
    }

    func testDifferentSongsSharingABeatAreNotRankedByOldSongID() {
        var tracker = RecognitionTracker()
        _ = tracker.observe([song()], start: 100, duration: 6, now: 106)
        _ = tracker.observe([song(at: 22)], start: 102, duration: 6, now: 108)
        let conflict = song(2, title: "Fantasy Theme", artist: "Kevin Krauter", at: 74, duration: 238)
        XCTAssertEqual(tracker.observe([conflict, song(at: 24)], start: 104, duration: 6, now: 110), .ambiguous)
        XCTAssertNil(tracker.confirmedID)
    }

    func testSameNameDoesNotMergeDifferentArtistIDs() {
        var first = song()
        first.artistIDs = [1142011]
        var second = song(2649579328)
        second.artistIDs = [94925390]
        var tracker = RecognitionTracker()
        XCTAssertEqual(tracker.observe([first, second], start: 0, duration: 6, now: 6), .ambiguous)
    }

    func testEquivalentAlbumEditionsCanShareAConfirmation() {
        var tracker = RecognitionTracker()
        _ = tracker.observe([song(), song(2)], start: 100, duration: 6, now: 106)
        XCTAssertEqual(tracker.observe([song(2, at: 22), song(at: 22)], start: 102, duration: 6, now: 108),
                       .accepted(song(2, at: 22)))
    }

    func testSeekOrSongChangeRequiresFreshEvidence() {
        var tracker = RecognitionTracker()
        _ = tracker.observe([song()], start: 100, duration: 6, now: 106)
        _ = tracker.observe([song(at: 22)], start: 102, duration: 6, now: 108)
        XCTAssertEqual(tracker.observe([song(at: 70)], start: 104, duration: 6, now: 110), .confirming)
        XCTAssertEqual(tracker.observe([song(at: 72)], start: 106, duration: 6, now: 112), .accepted(song(at: 72)))
        let other = song(3, title: "另一首", at: 0)
        XCTAssertEqual(tracker.observe([other], start: 108, duration: 6, now: 114), .confirming)
    }

    func testLateResponsesCannotOverwriteNewerPlayback() {
        var tracker = RecognitionTracker()
        XCTAssertEqual(tracker.observe([song()], start: 100, duration: 6, now: 111), .outdated)
        _ = tracker.observe([song()], start: 105, duration: 6, now: 111)
        XCTAssertEqual(tracker.observe([song()], start: 104, duration: 6, now: 111), .outdated)
    }

    func testMissingMatchesExpireOldLyrics() {
        var tracker = RecognitionTracker()
        _ = tracker.observe([song()], start: 100, duration: 6, now: 106)
        _ = tracker.observe([song(at: 22)], start: 102, duration: 6, now: 108)
        XCTAssertFalse(tracker.expire(at: 115))
        XCTAssertTrue(tracker.expire(at: 116.1))
        XCTAssertNil(tracker.confirmedID)
    }

    func testImpossibleOffsetsAndInconsistentVersionsAreRejected() {
        var tracker = RecognitionTracker()
        XCTAssertEqual(tracker.observe([song(at: 121)], start: 100, duration: 6, now: 106), .unmatched)
        XCTAssertEqual(tracker.observe([song(), song(2, at: 77)], start: 102, duration: 6, now: 108), .ambiguous)
    }

    func testAgainServiceResponsesCannotPublishUnrelatedLyrics() throws {
        struct Clip: Decodable {
            var sourceOffset: Double
            var seconds: Double
            var matches: [Match]
            struct Match: Decodable {
                var id: Int64
                var title: String
                var artists: [Artist]
                var duration: Double
                var startTime: Double
            }
            struct Artist: Decodable { var id: Int64; var name: String }
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "again-recognition", withExtension: "json", subdirectory: "Fixtures"))
        let clips = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: url))
        XCTAssertEqual(clips.count, 9)
        var tracker = RecognitionTracker()
        for clip in clips {
            let candidates = clip.matches.map {
                RecognitionCandidate(id: $0.id, title: $0.title, artist: $0.artists.map(\.name).joined(separator: " / "),
                                     artistIDs: $0.artists.map(\.id), duration: $0.duration / 1000, position: $0.startTime / 1000)
            }
            XCTAssertEqual(tracker.observe(candidates, start: clip.sourceOffset, duration: clip.seconds,
                                           now: clip.sourceOffset + clip.seconds + 0.5), .ambiguous)
        }
        XCTAssertNil(tracker.confirmedID)
    }
}
