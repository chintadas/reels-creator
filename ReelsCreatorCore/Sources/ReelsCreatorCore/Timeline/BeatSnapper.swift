import Foundation

public enum BeatSnapper {
    /// Computes per-clip durations, snapping photo cut boundaries to nearby detected beats
    /// when beat timestamps are available.
    public static func snapDurations(
        clips: [MediaClipSpec],
        beatTimestamps: [Double],
        minPhotoDuration: Double = 1.2,
        maxPhotoDuration: Double = 4.5,
        trimVideosToBeat: Bool = false
    ) -> [Double] {
        guard !clips.isEmpty else { return [] }

        let validBeats = beatTimestamps
            .filter { $0.isFinite && $0 >= 0 }
            .sorted()

        guard !validBeats.isEmpty else {
            return clips.map { max(0.1, $0.sourceDurationSeconds) }
        }

        var result: [Double] = []
        result.reserveCapacity(clips.count)
        var currentTime = 0.0

        for clip in clips {
            let baseDuration = max(0.1, clip.sourceDurationSeconds)
            let snappedDuration: Double

            switch clip.kind {
            case .photo:
                let clampedMin = min(minPhotoDuration, maxPhotoDuration)
                let clampedMax = max(minPhotoDuration, maxPhotoDuration)
                let windowStart = currentTime + clampedMin
                let windowEnd = currentTime + clampedMax
                let targetEnd = currentTime + min(max(baseDuration, clampedMin), clampedMax)

                let candidateBeats = validBeats.filter { $0 >= windowStart && $0 <= windowEnd }
                if let nearestBeat = candidateBeats.min(by: { abs($0 - targetEnd) < abs($1 - targetEnd) }) {
                    snappedDuration = max(0.1, nearestBeat - currentTime)
                } else {
                    snappedDuration = baseDuration
                }

            case .video:
                if trimVideosToBeat && baseDuration > minPhotoDuration {
                    let windowStart = currentTime + minPhotoDuration
                    let windowEnd = currentTime + baseDuration
                    if let beatBeforeEnd = validBeats.last(where: { $0 >= windowStart && $0 <= windowEnd }) {
                        snappedDuration = max(0.1, beatBeforeEnd - currentTime)
                    } else {
                        snappedDuration = baseDuration
                    }
                } else {
                    snappedDuration = baseDuration
                }
            }

            result.append(snappedDuration)
            currentTime += snappedDuration
        }

        return result
    }
}
