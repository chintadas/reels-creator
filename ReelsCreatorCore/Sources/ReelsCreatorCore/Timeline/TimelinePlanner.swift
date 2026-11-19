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
}

public struct PlannedTimeline: Equatable, Sendable {
    public let segments: [PlannedSegment]
    public let totalDurationSeconds: Double
    public let muteOriginalVideoClips: Bool
    public let backgroundAudioDurationSeconds: Double?

    public init(
        segments: [PlannedSegment],
        totalDurationSeconds: Double,
        muteOriginalVideoClips: Bool,
        backgroundAudioDurationSeconds: Double?
    ) {
        self.segments = segments
        self.totalDurationSeconds = totalDurationSeconds
        self.muteOriginalVideoClips = muteOriginalVideoClips
        self.backgroundAudioDurationSeconds = backgroundAudioDurationSeconds
    }
}

public enum TimelinePlanner {
    private struct RawSegmentSpec {
        let id: UUID
        let durationSeconds: Double
        let isOutro: Bool
        let keepOriginalAudio: Bool
    }

    public static func plan(
        clips: [MediaClipSpec],
        audio: AudioSelectionMode,
        outro: OutroSelectionMode,
        settings: ReelPolishSettings,
        beatTimestamps: [Double] = []
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

        let clipDurations: [Double]
        if settings.beatSyncEnabled && muteOriginalVideoClips && !beatTimestamps.isEmpty {
            clipDurations = BeatSnapper.snapDurations(clips: clips, beatTimestamps: beatTimestamps)
        } else {
            clipDurations = clips.map { max(0.1, $0.sourceDurationSeconds) }
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
        case .none:
            break
        case .staticLogo(_, let durationSeconds):
            rawSpecs.append(
                RawSegmentSpec(
                    id: UUID(),
                    durationSeconds: max(0.2, durationSeconds),
                    isOutro: true,
                    keepOriginalAudio: false
                )
            )
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

            if settings.crossfadeEnabled && settings.crossfadeDuration > 0 && index > 0 {
                let prev = plannedSegments[index - 1]
                let effectiveCrossfade = min(
                    settings.crossfadeDuration,
                    prev.durationSeconds / 3.0,
                    spec.durationSeconds / 3.0
                )

                if effectiveCrossfade > 0.01 {
                    plannedSegments[index - 1] = PlannedSegment(
                        id: prev.id,
                        index: prev.index,
                        trackIndex: prev.trackIndex,
                        startTimeSeconds: prev.startTimeSeconds,
                        durationSeconds: prev.durationSeconds,
                        fadeInDurationSeconds: prev.fadeInDurationSeconds,
                        fadeOutDurationSeconds: effectiveCrossfade,
                        isOutro: prev.isOutro,
                        keepOriginalAudio: prev.keepOriginalAudio
                    )
                    startTime = currentEndTime - effectiveCrossfade
                    fadeIn = effectiveCrossfade
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

        return PlannedTimeline(
            segments: plannedSegments,
            totalDurationSeconds: currentEndTime,
            muteOriginalVideoClips: muteOriginalVideoClips,
            backgroundAudioDurationSeconds: backgroundAudioDurationSeconds
        )
    }
}
