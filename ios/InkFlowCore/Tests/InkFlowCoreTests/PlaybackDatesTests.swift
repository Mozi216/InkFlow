import XCTest
@testable import InkFlowCore

final class PlaybackDatesTests: XCTestCase {
    func testAudioResumeDoesNotWaitForAnotherRecognition() {
        var clock = PlaybackClock()
        clock.duration = 200
        clock.align(position: 30, at: 100, running: true)
        clock.stop(at: 102)
        XCTAssertEqual(clock.value(at: 110), 32)
        XCTAssertTrue(clock.resume(at: 110))
        XCTAssertEqual(clock.value(at: 111), 33)
        // Repeated audio callbacks must not reset the timer origin.
        XCTAssertFalse(clock.resume(at: 111))
        XCTAssertEqual(clock.anchor, 110)
        // A delayed match can still correct a seek made during the interruption.
        clock.followAudio(position: 80, observedAt: 110, lastSound: 116, now: 116)
        XCTAssertEqual(clock.value(at: 116), 86)
    }

    func testFinishedSongDoesNotRestartWhenMoreAudioArrives() {
        var clock = PlaybackClock()
        clock.duration = 40
        clock.align(position: 38, at: 100, running: true)
        clock.stop(at: 104)
        XCTAssertFalse(clock.resume(at: 110))
        XCTAssertEqual(clock.value(at: 120), 40)
    }

    func testRepeatedAudioObservationsKeepTimerOriginStable() {
        var clock = PlaybackClock()
        clock.align(position: 30, at: 100, running: true)
        clock.followAudio(position: 34.05, observedAt: 104, lastSound: 110, now: 110)
        XCTAssertEqual(clock.anchor, 100)
        XCTAssertEqual(clock.value(at: 110), 40)
        clock.followAudio(position: 80, observedAt: 110, lastSound: 116, now: 116)
        XCTAssertEqual(clock.value(at: 116), 86)
    }

    func testRecognitionArrivingAfterPauseDoesNotRestartPlayback() {
        var clock = PlaybackClock()
        clock.followAudio(position: 30, observedAt: 100, lastSound: 98, now: 101)
        XCTAssertFalse(clock.running)
        XCTAssertEqual(clock.value(at: 200), 28)
        clock.followAudio(position: 28, observedAt: 201, lastSound: 201, now: 201.1)
        XCTAssertTrue(clock.running)
        XCTAssertEqual(clock.value(at: 202), 29)
    }

    func testTimerOriginDoesNotChangeOnRefreshOrWallClockJitter() {
        var clock = PlaybackClock()
        clock.align(position: 10, at: 100, running: true)
        var dates = PlaybackDates()
        dates.update(clock, at: 101, date: Date(timeIntervalSince1970: 1001))
        let original = dates.start
        for tick in 1...100 {
            dates.update(clock, at: 101 + Double(tick), date: Date(timeIntervalSince1970: 1001 + Double(tick) + 0.02))
            XCTAssertEqual(dates.start, original)
        }
    }

    func testPauseSeekResumeAndCalibrationReanchorTimers() {
        var clock = PlaybackClock()
        var dates = PlaybackDates()
        clock.align(position: 10, at: 100, running: true)
        dates.update(clock, at: 100, date: Date(timeIntervalSince1970: 1000))
        clock.stop(at: 102)
        dates.update(clock, at: 104, date: Date(timeIntervalSince1970: 1004))
        XCTAssertEqual(dates.start.timeIntervalSince1970, 992)
        clock.align(position: 3, at: 110, running: true)
        dates.update(clock, at: 111, date: Date(timeIntervalSince1970: 1011))
        XCTAssertEqual(dates.start.timeIntervalSince1970, 1007)
        dates.update(clock, at: 112, date: Date(timeIntervalSince1970: 1012), calibration: 0.3)
        XCTAssertEqual(dates.start.timeIntervalSince1970, 1006.7, accuracy: 0.0001)
    }

    func testCompactEnglishPreservesWordsAndTiming() {
        let line = LyricLine("Let the light stay with us until the morning comes", start: 0, end: 9)
        let parts = CompactLyrics.phrases(line)
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertEqual(parts.map(\.text).joined(separator: " "), line.text)
        for part in parts {
            XCTAssertEqual(CompactLyrics.phrase(line, at: part.start), part)
        }
        XCTAssertEqual(CompactLyrics.phrase(line, at: 100), parts.last)
    }

    func testFastCompactLyricsDoNotChangeForEveryCharacter() {
        let line = LyricLine("让风穿过安静的窗", start: 0, end: 2)
        let parts = CompactLyrics.phrases(line)
        XCTAssertEqual(parts.map(\.text).joined(), line.text)
        for (current, next) in zip(parts, parts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.start - current.start, 0.8)
        }
    }
}
