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

    func testLogoOverlayAndVideoOutroTimelineBehavior() throws {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0)
        ]
        let settings = ReelPolishSettings(
            crossfadeEnabled: true,
            crossfadeDuration: 0.3,
            beatSyncEnabled: false
        )

        let logoOverlayTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: settings
        )

        XCTAssertEqual(logoOverlayTimeline.segments.count, 1)
        XCTAssertFalse(logoOverlayTimeline.segments[0].isOutro)
        XCTAssertEqual(logoOverlayTimeline.totalDurationSeconds, 2.0, accuracy: 0.0001)
        let outroOverlay = try XCTUnwrap(logoOverlayTimeline.outroLogoOverlay)
        XCTAssertEqual(outroOverlay.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(outroOverlay.durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(outroOverlay.endTimeSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(outroOverlay.fadeInDurationSeconds, 0.3, accuracy: 0.0001)

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
        XCTAssertNil(videoOutroTimeline.outroLogoOverlay)
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

    func testIntroTextOverlaySpecTrimsAndRejectsBlankText() {
        XCTAssertNil(IntroTextOverlaySpec(rawText: ""))
        XCTAssertNil(IntroTextOverlaySpec(rawText: "   \n\t  "))

        let spec = IntroTextOverlaySpec(rawText: "  New\nArrivals  \n")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.text, "New\nArrivals")
        XCTAssertEqual(spec?.durationSeconds ?? 0, 3.0, accuracy: 0.0001)
        XCTAssertEqual(spec?.fadeInDurationSeconds ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(spec?.fadeOutDurationSeconds ?? 0, 0.4, accuracy: 0.0001)
    }

    func testIntroOverlaySpansOpeningClipsWithoutChangingTotalDuration() throws {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0),
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.5)
        ]
        let settings = ReelPolishSettings(
            crossfadeEnabled: true,
            crossfadeDuration: 0.4,
            beatSyncEnabled: false
        )
        let spec = try XCTUnwrap(IntroTextOverlaySpec(rawText: "Weekend Drop"))

        let baseline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .none,
            settings: settings
        )
        XCTAssertNil(baseline.introOverlay)

        let withIntro = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .none,
            settings: settings,
            introOverlay: spec
        )

        XCTAssertEqual(withIntro.totalDurationSeconds, baseline.totalDurationSeconds, accuracy: 0.0001)
        let overlay = try XCTUnwrap(withIntro.introOverlay)
        XCTAssertEqual(overlay.text, "Weekend Drop")
        XCTAssertEqual(overlay.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(overlay.durationSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(overlay.endTimeSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(overlay.fadeInDurationSeconds, 0.3, accuracy: 0.0001)
        XCTAssertEqual(overlay.fadeOutDurationSeconds, 0.4, accuracy: 0.0001)
    }

    func testIntroOverlayStopsBeforeVideoOutroWithAndWithoutCrossfade() throws {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0)
        ]
        let spec = try XCTUnwrap(IntroTextOverlaySpec(rawText: "Limited Release"))

        let noCrossfadeSettings = ReelPolishSettings(crossfadeEnabled: false)
        let noCrossfadeTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .videoClip(durationSeconds: 2.0),
            settings: noCrossfadeSettings,
            introOverlay: spec
        )
        let noCrossfadeOutro = try XCTUnwrap(noCrossfadeTimeline.segments.first(where: { $0.isOutro }))
        let noCrossfadeIntro = try XCTUnwrap(noCrossfadeTimeline.introOverlay)
        XCTAssertEqual(noCrossfadeOutro.startTimeSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(noCrossfadeIntro.durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(noCrossfadeIntro.endTimeSeconds, noCrossfadeOutro.startTimeSeconds, accuracy: 0.0001)

        let crossfadeSettings = ReelPolishSettings(crossfadeEnabled: true, crossfadeDuration: 0.4)
        let crossfadeTimeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .videoClip(durationSeconds: 2.0),
            settings: crossfadeSettings,
            introOverlay: spec
        )
        let crossfadeOutro = try XCTUnwrap(crossfadeTimeline.segments.first(where: { $0.isOutro }))
        let crossfadeIntro = try XCTUnwrap(crossfadeTimeline.introOverlay)
        XCTAssertEqual(crossfadeOutro.startTimeSeconds, 1.6, accuracy: 0.0001)
        XCTAssertEqual(crossfadeIntro.durationSeconds, 1.6, accuracy: 0.0001)
        XCTAssertEqual(crossfadeIntro.endTimeSeconds, crossfadeOutro.startTimeSeconds, accuracy: 0.0001)
    }

    func testIntroOverlayScalesFadesProportionallyForVeryShortReel() throws {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 0.5)
        ]
        let settings = ReelPolishSettings(crossfadeEnabled: false)
        let spec = try XCTUnwrap(IntroTextOverlaySpec(rawText: "Quick Flash"))

        let timeline = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .none,
            settings: settings,
            introOverlay: spec
        )

        let overlay = try XCTUnwrap(timeline.introOverlay)
        XCTAssertEqual(overlay.durationSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(overlay.fadeInDurationSeconds + overlay.fadeOutDurationSeconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(overlay.fadeInDurationSeconds, 0.5 * (0.3 / 0.7), accuracy: 0.0001)
        XCTAssertEqual(overlay.fadeOutDurationSeconds, 0.5 * (0.4 / 0.7), accuracy: 0.0001)
    }

    func testLogoOverlaySpansLastTwoSecondsWithoutExtendingDuration() throws {
        let clips = [
            MediaClipSpec(kind: .photo, sourceDurationSeconds: 3.0),
            MediaClipSpec(kind: .video, sourceDurationSeconds: 3.0)
        ]

        let noCrossfade = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: ReelPolishSettings(crossfadeEnabled: false)
        )
        XCTAssertEqual(noCrossfade.segments.count, 2)
        XCTAssertEqual(noCrossfade.totalDurationSeconds, 6.0, accuracy: 0.0001)
        let noCrossfadeLogo = try XCTUnwrap(noCrossfade.outroLogoOverlay)
        XCTAssertEqual(noCrossfadeLogo.startTimeSeconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(noCrossfadeLogo.durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(noCrossfadeLogo.endTimeSeconds, 6.0, accuracy: 0.0001)
        XCTAssertEqual(noCrossfadeLogo.fadeInDurationSeconds, 0.3, accuracy: 0.0001)

        let withCrossfade = TimelinePlanner.plan(
            clips: clips,
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: ReelPolishSettings(crossfadeEnabled: true, crossfadeDuration: 0.4)
        )
        XCTAssertEqual(withCrossfade.segments.count, 2)
        XCTAssertEqual(withCrossfade.totalDurationSeconds, 5.6, accuracy: 0.0001)
        let withCrossfadeLogo = try XCTUnwrap(withCrossfade.outroLogoOverlay)
        XCTAssertEqual(withCrossfadeLogo.startTimeSeconds, 3.6, accuracy: 0.0001)
        XCTAssertEqual(withCrossfadeLogo.durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(withCrossfadeLogo.endTimeSeconds, 5.6, accuracy: 0.0001)
    }

    func testLogoOverlayClampsForShortAndUltraShortReels() throws {
        let shortTimeline = TimelinePlanner.plan(
            clips: [MediaClipSpec(kind: .photo, sourceDurationSeconds: 1.2)],
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: ReelPolishSettings(crossfadeEnabled: false)
        )
        let shortLogo = try XCTUnwrap(shortTimeline.outroLogoOverlay)
        XCTAssertEqual(shortLogo.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(shortLogo.durationSeconds, 1.2, accuracy: 0.0001)
        XCTAssertEqual(shortLogo.fadeInDurationSeconds, 0.3, accuracy: 0.0001)

        let ultraShortTimeline = TimelinePlanner.plan(
            clips: [MediaClipSpec(kind: .photo, sourceDurationSeconds: 0.2)],
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: ReelPolishSettings(crossfadeEnabled: false)
        )
        let ultraShortLogo = try XCTUnwrap(ultraShortTimeline.outroLogoOverlay)
        XCTAssertEqual(ultraShortLogo.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(ultraShortLogo.durationSeconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(ultraShortLogo.fadeInDurationSeconds, 0.2, accuracy: 0.0001)
    }

    func testLogoOverlayReturnsNilForEmptyClips() {
        let timeline = TimelinePlanner.plan(
            clips: [],
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: ReelPolishSettings(crossfadeEnabled: false)
        )

        XCTAssertEqual(timeline.totalDurationSeconds, 0.0, accuracy: 0.0001)
        XCTAssertNil(timeline.outroLogoOverlay)
        XCTAssertNil(timeline.introOverlay)
    }

    func testIntroOverlayAndLogoOverlayAvoidOverlap() throws {
        let spec = try XCTUnwrap(IntroTextOverlaySpec(rawText: "New Drop"))
        let settings = ReelPolishSettings(crossfadeEnabled: false)

        // Long Reel (6.0s): intro [0.0, 3.0], outro [4.0, 6.0]
        let longTimeline = TimelinePlanner.plan(
            clips: [
                MediaClipSpec(kind: .photo, sourceDurationSeconds: 3.0),
                MediaClipSpec(kind: .photo, sourceDurationSeconds: 3.0)
            ],
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: settings,
            introOverlay: spec
        )
        let longIntro = try XCTUnwrap(longTimeline.introOverlay)
        let longOutro = try XCTUnwrap(longTimeline.outroLogoOverlay)
        XCTAssertEqual(longIntro.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(longIntro.endTimeSeconds, 3.0, accuracy: 0.0001)
        XCTAssertEqual(longOutro.startTimeSeconds, 4.0, accuracy: 0.0001)
        XCTAssertEqual(longOutro.endTimeSeconds, 6.0, accuracy: 0.0001)

        // Medium/short Reel (4.0s): intro trimmed to [0.0, 2.0], outro [2.0, 4.0]
        let mediumTimeline = TimelinePlanner.plan(
            clips: [
                MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0),
                MediaClipSpec(kind: .photo, sourceDurationSeconds: 2.0)
            ],
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: settings,
            introOverlay: spec
        )
        let mediumIntro = try XCTUnwrap(mediumTimeline.introOverlay)
        let mediumOutro = try XCTUnwrap(mediumTimeline.outroLogoOverlay)
        XCTAssertEqual(mediumIntro.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(mediumIntro.durationSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(mediumIntro.endTimeSeconds, mediumOutro.startTimeSeconds, accuracy: 0.0001)
        XCTAssertEqual(mediumOutro.startTimeSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(mediumOutro.endTimeSeconds, 4.0, accuracy: 0.0001)

        // Very short Reel (1.5s <= 2.0s): intro omitted, outro [0.0, 1.5]
        let veryShortTimeline = TimelinePlanner.plan(
            clips: [MediaClipSpec(kind: .photo, sourceDurationSeconds: 1.5)],
            audio: .none,
            outro: .logoOverlay(durationSeconds: 2.0),
            settings: settings,
            introOverlay: spec
        )
        XCTAssertNil(veryShortTimeline.introOverlay)
        let veryShortOutro = try XCTUnwrap(veryShortTimeline.outroLogoOverlay)
        XCTAssertEqual(veryShortOutro.startTimeSeconds, 0.0, accuracy: 0.0001)
        XCTAssertEqual(veryShortOutro.durationSeconds, 1.5, accuracy: 0.0001)
        XCTAssertEqual(veryShortOutro.endTimeSeconds, 1.5, accuracy: 0.0001)
    }

    func testDefaultPolishSettingsPhotoDuration() {
        let settings = ReelPolishSettings()
        XCTAssertEqual(settings.defaultPhotoDuration, 1.5, accuracy: 0.0001)
    }
}
