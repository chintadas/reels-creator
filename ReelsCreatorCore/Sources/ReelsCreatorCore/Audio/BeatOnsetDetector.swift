import Foundation

public enum BeatOnsetDetector {
    /// Detects beat onset timestamps from pre-computed per-window RMS energy values
    /// and their corresponding timestamps in seconds.
    public static func detectOnsets(
        energies: [Double],
        timestamps: [Double],
        cooldownSeconds: Double = 0.35,
        halfWindowRadius: Int = 8,
        localAverageMultiplier: Double = 1.4,
        globalPeakThresholdRatio: Double = 0.12
    ) -> [Double] {
        guard !energies.isEmpty,
              energies.count == timestamps.count,
              let globalPeak = energies.max(),
              globalPeak > 0 else {
            return []
        }

        let radius = max(0, halfWindowRadius)
        var detectedBeats: [Double] = []
        var lastBeatTimestamp = -cooldownSeconds

        for index in energies.indices {
            let start = max(0, index - radius)
            let end = min(energies.count - 1, index + radius)
            let slice = energies[start...end]
            let localAverage = slice.reduce(0, +) / Double(slice.count)

            let currentEnergy = energies[index]
            let prevEnergy = index > 0 ? energies[index - 1] : 0
            let timestamp = timestamps[index]

            let isOnsetPeak = currentEnergy > localAverage * localAverageMultiplier
                && currentEnergy > prevEnergy
                && currentEnergy > globalPeak * globalPeakThresholdRatio
                && (timestamp - lastBeatTimestamp) >= cooldownSeconds

            if isOnsetPeak {
                detectedBeats.append(timestamp)
                lastBeatTimestamp = timestamp
            }
        }

        return detectedBeats
    }
}
