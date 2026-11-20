import AVFoundation
import Foundation

enum VideoAudioExtractor {
    struct ExtractionResult: Sendable {
        let audioURL: URL
        let durationSeconds: Double
    }

    enum ExtractionError: LocalizedError {
        case noAudioTrack
        case emptyAudioTrack
        case compositionCreationFailed
        case exportSessionCreationFailed
        case exportFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                return "The selected video does not contain an audio track."
            case .emptyAudioTrack:
                return "The selected video's audio track is empty."
            case .compositionCreationFailed:
                return "Could not prepare the video's audio track for extraction."
            case .exportSessionCreationFailed:
                return "Could not initialize audio export for the selected video."
            case .exportFailed(let error):
                return "Could not extract audio from video: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }

    /// Extracts the primary audio track from the given video file into a temporary `.m4a` file.
    static func extractAudio(from videoURL: URL) async throws -> ExtractionResult {
        let sourceAsset = AVURLAsset(url: videoURL)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = audioTracks.first else {
            throw ExtractionError.noAudioTrack
        }

        let trackTimeRange = try await sourceAudioTrack.load(.timeRange)
        let sourceDuration: CMTime
        if trackTimeRange.duration.isValid && !trackTimeRange.duration.isIndefinite && trackTimeRange.duration > .zero {
            sourceDuration = trackTimeRange.duration
        } else {
            let assetDuration = try await sourceAsset.load(.duration)
            guard assetDuration.isValid && !assetDuration.isIndefinite && assetDuration > .zero else {
                throw ExtractionError.emptyAudioTrack
            }
            sourceDuration = assetDuration
        }

        guard CMTimeGetSeconds(sourceDuration) >= 0.05 else {
            throw ExtractionError.emptyAudioTrack
        }

        let sourceStart: CMTime
        if trackTimeRange.start.isValid && !trackTimeRange.start.isIndefinite && trackTimeRange.start >= .zero {
            sourceStart = trackTimeRange.start
        } else {
            sourceStart = .zero
        }
        let sourceRange = CMTimeRange(start: sourceStart, duration: sourceDuration)

        let composition = AVMutableComposition()
        guard let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExtractionError.compositionCreationFailed
        }
        try compAudioTrack.insertTimeRange(sourceRange, of: sourceAudioTrack, at: .zero)

        let outputURL = TemporaryMediaStore.makeTemporaryURL(prefix: "extracted-audio", fileExtension: "m4a")
        TemporaryMediaStore.removeItemIfPresent(outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExtractionError.exportSessionCreationFailed
        }

        do {
            try await exportSession.exportCompat(to: outputURL, as: .m4a)
        } catch {
            TemporaryMediaStore.removeItemIfPresent(outputURL)
            throw ExtractionError.exportFailed(error)
        }

        let exportedDuration = try await AVURLAsset(url: outputURL).load(.duration)
        let seconds = CMTimeGetSeconds(exportedDuration)
        guard seconds.isFinite && seconds > 0.05 else {
            TemporaryMediaStore.removeItemIfPresent(outputURL)
            throw ExtractionError.emptyAudioTrack
        }

        return ExtractionResult(audioURL: outputURL, durationSeconds: max(0.1, seconds))
    }
}
