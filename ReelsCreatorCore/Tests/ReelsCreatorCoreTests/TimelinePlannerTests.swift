import XCTest
@testable import ReelsCreatorCore

final class TimelinePlannerTests: XCTestCase {
    func testSequentialPlacementWithoutCrossfades() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.5),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 4.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 3.0)
        ]
        let settings = ReelPolishSettings(
            defaultPhotoDuration: 2.5,
            crossfadeEnabled: false,
            crossfadeDuration: 0.4,
            beatSyncEnabled: false
        )

        let timeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .none,
            settings: settings
        )

        XCTAssertEqual(timeline.segments.count, 3)
        XCTAssertEqual(timeline.totalDurationSeconds, 9.5, accuracy: 0.0001)
        XCTAssertFalse(timeline.muteOriginalVideoClips)
        XCTAssertNil(timeline.backgroundAudioDurationSeconds)

        XCTAssertEqual(timeline.segments[0].startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[0].durationSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[0].trackIndex, 0)
        XCTAssertEqual(timeline.segments[0].fadeInDurationSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[0].fadeOutDurationSeconds, 0.0, accuracy: 0.0001)

        XCTAssertEqual(timeline.segments[1].startTimeSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[1].durationSeconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[1].trackIndex, 0)

        XCTAssertEqual(timeline.segments[2].startTimeSeconds, 6.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[2].durationSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[2].trackIndex, 0)
    }

    func testOverlappingABTrackPlacementWithCrossfades() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 3.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 3.0),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 3.0)
        ]
        let settings = ReelPolishSettings(
            defaultPhotoDuration: 3.0,
            crossfadeEnabled: true,
            crossfadeDuration: 0.5,
            beatSyncEnabled: false
        )

        let timeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .none,
            settings: settings
        )

        XCTAssertEqual(timeline.segments.count, 3)
        XCTAssertEqual(timeline.segments[0].trackIndex, 0)
        XCTAssertEqual(timeline.segments[1].trackIndex, 1)
        XCTAssertEqual(timeline.segments[2].trackIndex, 0)

        XCTAssertEqual(timeline.segments[0].startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[0].fadeInDurationSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[0].fadeOutDurationSeconds, 0.5, accuracy: 0.0001)

        XCTAssertEqual(timeline.segments[1].startTimeSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[1].fadeInDurationSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[1].fadeOutDurationSeconds, 0.5, accuracy: 0.0001)

        XCTAssertEqual(timeline.segments[2].startTimeSeconds, 5.0, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[2].fadeInDurationSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[2].fadeOutDurationSeconds, 0.0, accuracy: 0.0001)

        XCTAssertEqual(timeline.totalDurationSeconds, 8.0, accuracy: 0.0001)
    }

    func testCrossfadeClampsForShortClips() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 0.6),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 0.9)
        ]
        let settings = ReelPolishSettings(
            crossfadeEnabled: true,
            crossfadeDuration: 0.5,
            beatSyncEnabled: false
        )

        let timeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .none,
            settings: settings
        )

        XCTAssertEqual(timeline.segments[0].fadeOutDurationSeconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[1].fadeInDurationSeconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(timeline.segments[1].startTimeSeconds, 0.4, accuracy: 0.0001)
        XCTAssertEqual(timeline.totalDurationSeconds, 1.3, accuracy: 0.0001)
    }

    func testBeatSnappingPhotoDurations() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.5),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 3.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.5)
        ]
        let beats = [0.5, 2.2, 4.9, 5.4, 7.6, 8.2]
        let audioURL = URL(fileURLWithPath: "/tmp/track.m4a")
        let settings = ReelPolishSettings(
            defaultPhotoDuration: 2.5,
            crossfadeEnabled: false,
            crossfadeDuration: 0.0,
            beatSyncEnabled: true
        )

        let timeline = TimelinePlanner.plan(
            clips: clips,
            audio: .customTrack(url: audioURL, durationSeconds: 20.0),
            outro: .none,
            settings: settings,
            beatTimestamps: beats
        )

        // Photo 1: current=0.0, targetEnd=2.5, window=[1.2...4.5] -> nearest beat is 2.2 -> duration 2.2
        XCTAssertEqual(timeline.segments[0].durationSeconds, 2.2, accuracy: 0.0001)
        // Video 2: current=2.2, keeps sourceDurationSeconds = 3.0 -> cumulative=5.2
        XCTAssertEqual(timeline.segments[1].durationSeconds, 3.0, accuracy: 0.0001)
        // Photo 3: current=5.2, targetEnd=7.7, window=[6.4...9.7] -> nearest beat is 7.6 -> duration 2.4
        XCTAssertEqual(timeline.segments[2].durationSeconds, 2.4, accuracy: 0.0001)
    }

    func testAppendingStaticLogoAndVideoOutroSegments() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0)
        ]
        let settings = ReelPolishSettings(
            crossfadeEnabled: true,
            crossfadeDuration: 0.3,
            beatSyncEnabled: false
        )

        let staticTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .staticLogo(backgroundColorHex: "#112233", durationSeconds: 2.0),
            settings: settings
        )

        XCTAssertEqual(staticTimeline.segments.count, 2)
        XCTAssertFalse(staticTimeline.segments[0].isOutro)
        XCTAssertTrue(staticTimeline.segments[1].isOutro)
        XCTAssertFalse(staticTimeline.segments[1].keepOriginalAudio)
        XCTAssertEqual(staticTimeline.segments[1].durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(staticTimeline.totalDurationSeconds, 3.7, accuracy: 0.0001)

        let videoOutroTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .videoClip(durationSeconds: 3.0),
            settings: settings
        )

        XCTAssertEqual(videoOutroTimeline.segments.count, 2)
        XCTAssertTrue(videoOutroTimeline.segments[1].isOutro)
        XCTAssertTrue(videoOutroTimeline.segments[1].keepOriginalAudio)
        XCTAssertEqual(videoOutroTimeline.totalDurationSeconds, 4.7, accuracy: 0.0001)
    }

    func testOriginalVideoAudioMutedWhenCustomAudioSelectedAndPreservedWhenNone() {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 4.0)
        ]
        let settings = ReelPolishSettings(crossfadeEnabled: false)
        let audioURL = URL(fileURLWithPath: "/tmp/music.mp3")

        let noMusicTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .videoClip(durationSeconds: 2.0),
            settings: settings
        )
        XCTAssertFalse(noMusicTimeline.muteOriginalVideoClips)
        XCTAssertFalse(noMusicTimeline.segments[0].keepOriginalAudio) // photo
        XCTAssertTrue(noMusicTimeline.segments[1].keepOriginalAudio)  // video
        XCTAssertTrue(noMusicTimeline.segments[2].keepOriginalAudio)  // video outro

        let customAudioTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .customTrack(url: audioURL, durationSeconds: 15.0),
            outro: .videoClip(durationSeconds: 2.0),
            settings: settings
        )
        XCTAssertTrue(customAudioTimeline.muteOriginalVideoClips)
        XCTAssertEqual(customAudioTimeline.backgroundAudioDurationSeconds, 15.0)
        XCTAssertFalse(customAudioTimeline.segments[0].keepOriginalAudio)
        XCTAssertFalse(customAudioTimeline.segments[1].keepOriginalAudio)
        XCTAssertFalse(customAudioTimeline.segments[2].keepOriginalAudio)
    }
}
