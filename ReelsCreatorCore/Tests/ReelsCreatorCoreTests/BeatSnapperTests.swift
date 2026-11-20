import XCTest
@testable import ReelsCreatorCore

final class BeatSnapperTests: XCTestCase {
    func testEmptyClipsAndEmptyBeats() {
        XCTAssertEqual(
            BeatSnapper.snapDurations(clips: [], beatTimestamps: [1.0, 2.0]),
            []
        )

        let clips = [
            MediaClipSpec(kind: .photo),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 3.2)
        ]
        let noBeatDurations = BeatSnapper.snapDurations(
            clips: clips,
            beatTimestamps: [],
            defaultPhotoDuration: 2.0
        )
        XCTAssertEqual(noBeatDurations.count, 2)
        XCTAssertEqual(noBeatDurations[0], 2.0, accuracy: 0.0001)
        XCTAssertEqual(noBeatDurations[1], 3.2, accuracy: 0.0001)
    }

    func testFiltersInvalidAndUnsortedBeats() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0)
        ]
        let messyBeats = [Double.nan, -1.5, 4.1, Double.infinity, 1.8, -0.1]

        let durations = BeatSnapper.snapDurations(clips: clips, beatTimestamps: messyBeats)
        XCTAssertEqual(durations.count, 2)
        // Photo 1 snaps to 1.8; Photo 2 starts at 1.8 and snaps to 4.1 (duration 2.3).
        XCTAssertEqual(durations[0], 1.8, accuracy: 0.0001)
        XCTAssertEqual(durations[1], 2.3, accuracy: 0.0001)
    }

    func testOutOfWindowBeatsFallBackToBaseDuration() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0)
        ]
        // First clip window is [1.2, 4.5]: 0.5 and 5.0 are outside, so falls back to 2.0.
        // Second clip starts at 2.0, window [3.2, 6.5]: snaps to 5.0 (duration 3.0).
        let durations = BeatSnapper.snapDurations(
            clips: clips,
            beatTimestamps: [0.5, 5.0]
        )

        XCTAssertEqual(durations[0], 2.0, accuracy: 0.0001)
        XCTAssertEqual(durations[1], 3.0, accuracy: 0.0001)
    }

    func testTrimVideosToBeatTrimsToLastInWindowBeatAndFallsBack() {
        let clips = [
            MediaClipSpec(kind: .video, sourceDurationSeconds: 4.0),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 4.0)
        ]
        // Video 1 (0..4.0): window [1.2, 4.0] -> last beat is 3.5 -> trimmed to 3.5.
        // Video 2 (3.5..7.5): window [4.7, 7.5] -> no beat inside -> falls back to 4.0.
        let durations = BeatSnapper.snapDurations(
            clips: clips,
            beatTimestamps: [1.5, 3.5, 4.2, 8.2],
            trimVideosToBeat: true
        )

        XCTAssertEqual(durations[0], 3.5, accuracy: 0.0001)
        XCTAssertEqual(durations[1], 4.0, accuracy: 0.0001)
    }

    func testCrossfadeAlignmentIncludingShortClipClamping() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 1.0)
        ]
        // Clip 1 snaps to beat 2.0.
        // Clip 2 allows minPhotoDuration=0.6 with crossfadeDuration=0.5.
        // Beat 2.6 requires rawDelta=0.6 -> clamped overlap nextDuration/3 = 0.3 -> duration 0.9.
        // Timeline check: start = 2.0 - 0.3 = 1.7, end = 1.7 + 0.9 = 2.6.
        let durations = BeatSnapper.snapDurations(
            clips: clips,
            beatTimestamps: [2.0, 2.6],
            minPhotoDuration: 0.6,
            maxPhotoDuration: 3.0,
            crossfadeDuration: 0.5
        )

        XCTAssertEqual(durations[0], 2.0, accuracy: 0.0001)
        XCTAssertEqual(durations[1], 0.9, accuracy: 0.0001)

        let timeline = TimelinePlanner.plan(
            clips: clips,
            audio: .customTrack(url: URL(fileURLWithPath: "/tmp/a.m4a"), durationSeconds: 10.0),
            outro: .none,
            settings: ReelPolishSettings(crossfadeEnabled: true, crossfadeDuration: 0.5, beatSyncEnabled: true),
            beatTimestamps: [2.0, 2.6]
        )
        // With default minPhotoDuration=1.2 inside TimelinePlanner.plan, beat 2.6 needs duration 0.9 (<1.2),
        // so clip 2 keeps 1.0; verify directly with BeatSnapper output placed sequentially with overlap:
        let overlap = min(0.5, durations[0] / 3.0, durations[1] / 3.0)
        XCTAssertEqual(durations[0] - overlap + durations[1], 2.6, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments.count, 2)
    }
}
