import Accelerate
import AVFoundation
import Foundation
import ReelsCreatorCore

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

    /// Analyzes the audio track using RMS window energy spikes (`vDSP_rmsqv`) across all channels
    /// and returns beat timestamps in seconds suitable for snapping photo cuts.
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
            let channelCount = Int(format.channelCount)

            guard sampleRate > 0, totalFrames > 0, channelCount > 0 else {
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

                let frameLength = vDSP_Length(buffer.frameLength)
                var sumSquaredRMS = 0.0
                for channel in 0..<channelCount {
                    var channelRMS: Float = 0
                    vDSP_rmsqv(channelData[channel], 1, &channelRMS, frameLength)
                    let value = Double(channelRMS)
                    sumSquaredRMS += value * value
                }
                let combinedRMS = sqrt(sumSquaredRMS / Double(channelCount))

                energies.append(combinedRMS)
                timestamps.append(Double(processedFrames) / sampleRate)
                processedFrames += AVAudioFramePosition(buffer.frameLength)
            }

            return BeatOnsetDetector.detectOnsets(
                energies: energies,
                timestamps: timestamps,
                cooldownSeconds: cooldownSeconds
            )
        }.value
    }
}
