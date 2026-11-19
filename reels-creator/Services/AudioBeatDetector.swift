import Accelerate
import AVFoundation
import Foundation

enum AudioBeatDetector {
    enum BeatDetectorError: LocalizedError {
        case emptyAudioFile
        case unsupportedAudioFormat

        var errorDescription: String? {
            switch self {
            case .emptyAudioFile:
                return "The selected audio file contains no audio frames."
            case .unsupportedAudioFormat:
                return "Could not decode float PCM samples from the selected audio file."
            }
        }
    }

    /// Analyzes the audio track using RMS window energy spikes (`vDSP_rmsqv`) and returns
    /// beat timestamps in seconds suitable for snapping photo cuts.
    static func detectBeats(
        in audioURL: URL,
        windowDuration: Double = 0.05,
        cooldownSeconds: Double = 0.35
    ) async throws -> [Double] {
        try await Task.detached(priority: .userInitiated) {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let format = audioFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = audioFile.length

            guard sampleRate > 0, totalFrames > 0 else {
                throw BeatDetectorError.emptyAudioFile
            }

            let framesPerWindow = max(1, AVAudioFrameCount(sampleRate * windowDuration))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerWindow) else {
                throw BeatDetectorError.unsupportedAudioFormat
            }

            var energies: [Double] = []
            var timestamps: [Double] = []
            var processedFrames: AVAudioFramePosition = 0

            while processedFrames < totalFrames {
                buffer.frameLength = 0
                try audioFile.read(into: buffer)
                guard buffer.frameLength > 0 else { break }

                guard let channelData = buffer.floatChannelData else {
                    throw BeatDetectorError.unsupportedAudioFormat
                }

                var rms: Float = 0
                vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(buffer.frameLength))

                energies.append(Double(rms))
                timestamps.append(Double(processedFrames) / sampleRate)
                processedFrames += AVAudioFramePosition(buffer.frameLength)
            }

            guard !energies.isEmpty else { return [] }

            let globalPeak = energies.max() ?? 0
            guard globalPeak > 0 else { return [] }

            let halfRadius = 8
            var detectedBeats: [Double] = []
            var lastBeatTimestamp = -cooldownSeconds

            for index in energies.indices {
                let start = max(0, index - halfRadius)
                let end = min(energies.count - 1, index + halfRadius)
                let slice = energies[start...end]
                let localAverage = slice.reduce(0, +) / Double(slice.count)

                let currentEnergy = energies[index]
                let prevEnergy = index > 0 ? energies[index - 1] : 0
                let timestamp = timestamps[index]

                let isOnsetPeak = currentEnergy > localAverage * 1.4
                    && currentEnergy > prevEnergy
                    && currentEnergy > globalPeak * 0.12
                    && (timestamp - lastBeatTimestamp) >= cooldownSeconds

                if isOnsetPeak {
                    detectedBeats.append(timestamp)
                    lastBeatTimestamp = timestamp
                }
            }

            return detectedBeats
        }.value
    }
}
