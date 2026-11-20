import Foundation

public enum BeatSnapper {
    /// Computes per-clip durations, snapping photo cut boundaries to nearby detected beats
    /// when beat timestamps are available, accounting for crossfade overlaps so cuts land on beats.
    public static func snapDurations(
        clips: [MediaClipSpec],
        beatTimestamps: [Double],
        minPhotoDuration: Double = 1.2,
        maxPhotoDuration: Double = 4.5,
        trimVideosToBeat: Bool = false,
        crossfadeDuration: Double = 0.0,
        defaultPhotoDuration: Double = 1.5
    ) -> [Double] {
        guard !clips.isEmpty else { return [] }

        let validBeats = beatTimestamps
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        guard !validBeats.isEmpty else {
            return clips.map { $0.resolvedSourceDuration(defaultPhotoDuration: defaultPhotoDuration) }
        }

        let clampedMin = min(minPhotoDuration, maxPhotoDuration)
        let clampedMax = max(minPhotoDuration, maxPhotoDuration)

        var result: [Double] = []
        result.reserveCapacity(clips.count)
        var previousEndTime = 0.0
        var previousDuration: Double?

        func durationToReach(beat: Double) -> Double? {
            guard let prevDur = previousDuration, crossfadeDuration > 0 else {
                return beat - previousEndTime
            }

            let rawDelta = beat - previousEndTime
            guard rawDelta > 0 else { return nil }

            let maxPrevOverlap = min(crossfadeDuration, prevDur / 3.0)
            let effectivePrevOverlap = maxPrevOverlap > 0.01 ? maxPrevOverlap : 0.0

            // Case 1: Overlap capped by previous clip or crossfadeDuration (or zero if below threshold).
            let candidate1 = rawDelta + effectivePrevOverlap
            let overlap1 = TimelinePlanner.effectiveCrossfade(
                requested: crossfadeDuration,
                previousDuration: prevDur,
                nextDuration: candidate1
            )
            if abs(overlap1 - effectivePrevOverlap) < 1e-9 {
                return candidate1
            }

            // Case 2: Overlap capped by nextDuration / 3.0, so rawDelta = (2/3) * candidate.
            let candidate2 = rawDelta * 1.5
            if candidate2 / 3.0 > 0.01 {
                let overlap2 = TimelinePlanner.effectiveCrossfade(
                    requested: crossfadeDuration,
                    previousDuration: prevDur,
                    nextDuration: candidate2
                )
                if abs((previousEndTime - overlap2 + candidate2) - beat) < 1e-6 {
                    return candidate2
                }
            }

            return rawDelta
        }

        for clip in clips {
            let baseDuration = clip.resolvedSourceDuration(defaultPhotoDuration: defaultPhotoDuration)
            let snappedDuration: Double

            switch clip.kind {
            case .photo:
                let clampedTarget = min(max(baseDuration, clampedMin), clampedMax)
                let targetOverlap: Double
                if let prevDur = previousDuration, crossfadeDuration > 0 {
                    targetOverlap = TimelinePlanner.effectiveCrossfade(
                        requested: crossfadeDuration,
                        previousDuration: prevDur,
                        nextDuration: clampedTarget
                    )
                } else {
                    targetOverlap = 0.0
                }
                let targetEnd = previousEndTime - targetOverlap + clampedTarget

                let candidates: [(beat: Double, duration: Double)] = validBeats.compactMap { beat in
                    guard let duration = durationToReach(beat: beat),
                          duration >= clampedMin - 1e-9,
                          duration <= clampedMax + 1e-9 else {
                        return nil
                    }
                    return (beat, duration)
                }

                if let nearest = candidates.min(by: { abs($0.beat - targetEnd) < abs($1.beat - targetEnd) }) {
                    snappedDuration = max(0.1, nearest.duration)
                } else {
                    snappedDuration = baseDuration
                }

            case .video:
                if trimVideosToBeat && baseDuration > clampedMin {
                    let candidates: [(beat: Double, duration: Double)] = validBeats.compactMap { beat in
                        guard let duration = durationToReach(beat: beat),
                              duration >= clampedMin - 1e-9,
                              duration <= baseDuration + 1e-9 else {
                            return nil
                        }
                        return (beat, duration)
                    }
                    if let beatBeforeEnd = candidates.last {
                        snappedDuration = max(0.1, beatBeforeEnd.duration)
                    } else {
                        snappedDuration = baseDuration
                    }
                } else {
                    snappedDuration = baseDuration
                }
            }

            let actualOverlap: Double
            if let prevDur = previousDuration, crossfadeDuration > 0 {
                actualOverlap = TimelinePlanner.effectiveCrossfade(
                    requested: crossfadeDuration,
                    previousDuration: prevDur,
                    nextDuration: snappedDuration
                )
            } else {
                actualOverlap = 0.0
            }

            result.append(snappedDuration)
            previousEndTime = previousEndTime - actualOverlap + snappedDuration
            previousDuration = snappedDuration
        }

        return result
    }
}
