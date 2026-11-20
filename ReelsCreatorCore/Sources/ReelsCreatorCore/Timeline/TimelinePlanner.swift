import Foundation

public struct PlannedSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let index: Int
    public let trackIndex: Int
    public let startTimeSeconds: Double
    public let durationSeconds: Double
    public let fadeInDurationSeconds: Double
    public let fadeOutDurationSeconds: Double
    public let isOutro: Bool
    public let keepOriginalAudio: Bool

    public init(
        id: UUID,
        index: Int,
        trackIndex: Int,
        startTimeSeconds: Double,
        durationSeconds: Double,
        fadeInDurationSeconds: Double,
        fadeOutDurationSeconds: Double,
        isOutro: Bool,
        keepOriginalAudio: Bool
    ) {
        self.id = id
        self.index = index
        self.trackIndex = trackIndex
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.fadeInDurationSeconds = fadeInDurationSeconds
        self.fadeOutDurationSeconds = fadeOutDurationSeconds
        self.isOutro = isOutro
        self.keepOriginalAudio = keepOriginalAudio
    }

    public var endTimeSeconds: Double {
        startTimeSeconds + durationSeconds
    }

    internal func withFadeOut(_ fadeOutDurationSeconds: Double) -> PlannedSegment {
        PlannedSegment(
            id: id,
            index: index,
            trackIndex: trackIndex,
            startTimeSeconds: startTimeSeconds,
            durationSeconds: durationSeconds,
            fadeInDurationSeconds: fadeInDurationSeconds,
            fadeOutDurationSeconds: fadeOutDurationSeconds,
            isOutro: isOutro,
            keepOriginalAudio: keepOriginalAudio
        )
    }
}

public struct PlannedIntroOverlay: Equatable, Sendable {
    public let text: String
    public let startTimeSeconds: Double
    public let durationSeconds: Double
    public let fadeInDurationSeconds: Double
    public let fadeOutDurationSeconds: Double

    public init(
        text: String,
        startTimeSeconds: Double = 0.0,
        durationSeconds: Double,
        fadeInDurationSeconds: Double,
        fadeOutDurationSeconds: Double
    ) {
        self.text = text
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.fadeInDurationSeconds = fadeInDurationSeconds
        self.fadeOutDurationSeconds = fadeOutDurationSeconds
    }

    public var endTimeSeconds: Double {
        startTimeSeconds + durationSeconds
    }
}

public struct PlannedOutroLogoOverlay: Equatable, Sendable {
    public let startTimeSeconds: Double
    public let durationSeconds: Double
    public let fadeInDurationSeconds: Double

    public init(
        startTimeSeconds: Double,
        durationSeconds: Double,
        fadeInDurationSeconds: Double
    ) {
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.fadeInDurationSeconds = fadeInDurationSeconds
    }

    public var endTimeSeconds: Double {
        startTimeSeconds + durationSeconds
    }
}

public struct PlannedOverlays: Equatable, Sendable {
    public let introOverlay: PlannedIntroOverlay?
    public let outroLogoOverlay: PlannedOutroLogoOverlay?

    public init(
        introOverlay: PlannedIntroOverlay?,
        outroLogoOverlay: PlannedOutroLogoOverlay?
    ) {
        self.introOverlay = introOverlay
        self.outroLogoOverlay = outroLogoOverlay
    }
}

public struct PlannedTimeline: Equatable, Sendable {
    public let segments: [PlannedSegment]
    public let totalDurationSeconds: Double
    public let muteOriginalVideoClips: Bool
    public let backgroundAudioDurationSeconds: Double?
    public let introOverlay: PlannedIntroOverlay?
    public let outroLogoOverlay: PlannedOutroLogoOverlay?

    public init(
        segments: [PlannedSegment],
        totalDurationSeconds: Double,
        muteOriginalVideoClips: Bool,
        backgroundAudioDurationSeconds: Double?,
        introOverlay: PlannedIntroOverlay? = nil,
        outroLogoOverlay: PlannedOutroLogoOverlay? = nil
    ) {
        self.segments = segments
        self.totalDurationSeconds = totalDurationSeconds
        self.muteOriginalVideoClips = muteOriginalVideoClips
        self.backgroundAudioDurationSeconds = backgroundAudioDurationSeconds
        self.introOverlay = introOverlay
        self.outroLogoOverlay = outroLogoOverlay
    }
}

public enum TimelinePlanner {
    private struct RawSegmentSpec {
        let id: UUID
        let durationSeconds: Double
        let isOutro: Bool
        let keepOriginalAudio: Bool
    }

    internal static func effectiveCrossfade(
        requested: Double,
        previousDuration: Double,
        nextDuration: Double
    ) -> Double {
        guard requested > 0 else { return 0.0 }
        let value = min(requested, previousDuration / 3.0, nextDuration / 3.0)
        return value > 0.01 ? value : 0.0
    }

    public static func resolveIntroOverlay(
        _ spec: IntroTextOverlaySpec?,
        maxEndTimeSeconds: Double
    ) -> PlannedIntroOverlay? {
        guard let spec else { return nil }
        let effectiveDuration = min(spec.durationSeconds, max(0, maxEndTimeSeconds))
        guard effectiveDuration > 0.01 else { return nil }

        var fadeIn = spec.fadeInDurationSeconds
        var fadeOut = spec.fadeOutDurationSeconds
        let totalFade = fadeIn + fadeOut
        if totalFade > effectiveDuration, totalFade > 0 {
            let scale = effectiveDuration / totalFade
            fadeIn *= scale
            fadeOut *= scale
        }

        return PlannedIntroOverlay(
            text: spec.text,
            startTimeSeconds: 0.0,
            durationSeconds: effectiveDuration,
            fadeInDurationSeconds: fadeIn,
            fadeOutDurationSeconds: fadeOut
        )
    }

    public static func resolveOutroLogoOverlay(
        durationSeconds: Double,
        fadeInDurationSeconds: Double,
        totalDurationSeconds: Double
    ) -> PlannedOutroLogoOverlay? {
        guard durationSeconds > 0, totalDurationSeconds > 0.01 else {
            return nil
        }

        let effectiveDuration = min(durationSeconds, totalDurationSeconds)
        guard effectiveDuration > 0.01 else {
            return nil
        }

        let startTimeSeconds = max(0.0, totalDurationSeconds - effectiveDuration)
        let clampedFadeIn = min(max(0.0, fadeInDurationSeconds), effectiveDuration)

        return PlannedOutroLogoOverlay(
            startTimeSeconds: startTimeSeconds,
            durationSeconds: effectiveDuration,
            fadeInDurationSeconds: clampedFadeIn
        )
    }

    public static func resolveOverlays(
        intro: IntroTextOverlaySpec?,
        outro: OutroSelectionMode,
        outroVideoStartTimeSeconds: Double? = nil,
        totalDurationSeconds: Double
    ) -> PlannedOverlays {
        let outroLogoOverlay: PlannedOutroLogoOverlay?
        if case .logoOverlay(let durationSeconds, let fadeInDurationSeconds) = outro {
            outroLogoOverlay = resolveOutroLogoOverlay(
                durationSeconds: durationSeconds,
                fadeInDurationSeconds: fadeInDurationSeconds,
                totalDurationSeconds: totalDurationSeconds
            )
        } else {
            outroLogoOverlay = nil
        }

        let maxIntroEnd = outroVideoStartTimeSeconds
            ?? outroLogoOverlay?.startTimeSeconds
            ?? totalDurationSeconds
        let introOverlay = resolveIntroOverlay(intro, maxEndTimeSeconds: maxIntroEnd)

        return PlannedOverlays(
            introOverlay: introOverlay,
            outroLogoOverlay: outroLogoOverlay
        )
    }

    public static func plan(
        clips: [MediaClipSpec],
        audio: AudioSelectionMode,
        outro: OutroSelectionMode,
        settings: ReelPolishSettings,
        beatTimestamps: [Double] = [],
        introOverlay: IntroTextOverlaySpec? = nil
    ) -> PlannedTimeline {
        let muteOriginalVideoClips: Bool
        let backgroundAudioDurationSeconds: Double?

        switch audio {
        case .none:
            muteOriginalVideoClips = false
            backgroundAudioDurationSeconds = nil
        case .customTrack(_, let durationSeconds):
            muteOriginalVideoClips = true
            backgroundAudioDurationSeconds = max(0, durationSeconds)
        }

        let requestedCrossfade = settings.crossfadeEnabled ? max(0, settings.crossfadeDuration) : 0.0

        let clipDurations: [Double]
        if settings.beatSyncEnabled && muteOriginalVideoClips && !beatTimestamps.isEmpty {
            clipDurations = BeatSnapper.snapDurations(
                clips: clips,
                beatTimestamps: beatTimestamps,
                crossfadeDuration: requestedCrossfade,
                defaultPhotoDuration: settings.defaultPhotoDuration
            )
        } else {
            clipDurations = clips.map { $0.resolvedSourceDuration(defaultPhotoDuration: settings.defaultPhotoDuration) }
        }

        var rawSpecs: [RawSegmentSpec] = zip(clips, clipDurations).map { clip, duration in
            RawSegmentSpec(
                id: clip.id,
                durationSeconds: duration,
                isOutro: false,
                keepOriginalAudio: (clip.kind == .video) && !muteOriginalVideoClips
            )
        }

        switch outro {
        case .none, .logoOverlay:
            break
        case .videoClip(let durationSeconds):
            rawSpecs.append(
                RawSegmentSpec(
                    id: UUID(),
                    durationSeconds: max(0.2, durationSeconds),
                    isOutro: true,
                    keepOriginalAudio: !muteOriginalVideoClips
                )
            )
        }

        var plannedSegments: [PlannedSegment] = []
        plannedSegments.reserveCapacity(rawSpecs.count)
        var currentEndTime = 0.0

        for (index, spec) in rawSpecs.enumerated() {
            let trackIndex = settings.crossfadeEnabled ? (index % 2) : 0
            var startTime = currentEndTime
            var fadeIn = 0.0

            if settings.crossfadeEnabled && requestedCrossfade > 0 && index > 0 {
                let prev = plannedSegments[index - 1]
                let overlap = effectiveCrossfade(
                    requested: requestedCrossfade,
                    previousDuration: prev.durationSeconds,
                    nextDuration: spec.durationSeconds
                )

                if overlap > 0 {
                    plannedSegments[index - 1] = prev.withFadeOut(overlap)
                    startTime = currentEndTime - overlap
                    fadeIn = overlap
                }
            }

            let segment = PlannedSegment(
                id: spec.id,
                index: index,
                trackIndex: trackIndex,
                startTimeSeconds: startTime,
                durationSeconds: spec.durationSeconds,
                fadeInDurationSeconds: fadeIn,
                fadeOutDurationSeconds: 0.0,
                isOutro: spec.isOutro,
                keepOriginalAudio: spec.keepOriginalAudio
            )
            plannedSegments.append(segment)
            currentEndTime = segment.endTimeSeconds
        }

        let overlays = resolveOverlays(
            intro: introOverlay,
            outro: outro,
            outroVideoStartTimeSeconds: plannedSegments.first(where: { $0.isOutro })?.startTimeSeconds,
            totalDurationSeconds: currentEndTime
        )

        return PlannedTimeline(
            segments: plannedSegments,
            totalDurationSeconds: currentEndTime,
            muteOriginalVideoClips: muteOriginalVideoClips,
            backgroundAudioDurationSeconds: backgroundAudioDurationSeconds,
            introOverlay: overlays.introOverlay,
            outroLogoOverlay: overlays.outroLogoOverlay
        )
    }
}
