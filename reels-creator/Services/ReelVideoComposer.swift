import AVFoundation
import Foundation
import ReelsCreatorCore
import UIKit

struct ReelCompositionRequest {
    let items: [SelectedMediaItem]
    let audioMode: AudioSelectionMode
    let outroMode: OutroSelectionMode
    let outroLogoImage: UIImage?
    let outroBackgroundColor: UIColor
    let outroVideoURL: URL?
    let polishSettings: ReelPolishSettings
}

enum ReelVideoComposer {
    enum ComposerError: LocalizedError {
        case noMediaSelected
        case missingPhotoImage(String)
        case missingVideoURL(String)
        case missingVideoTrack(String)
        case missingOutroLogoImage
        case missingOutroVideoURL
        case exportSessionCreationFailed
        case exportFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .noMediaSelected:
                return "Please select at least one photo or video."
            case .missingPhotoImage(let title):
                return "Could not load image data for \(title)."
            case .missingVideoURL(let title):
                return "Could not locate video file for \(title)."
            case .missingVideoTrack(let title):
                return "The clip \"\(title)\" does not contain a valid video track."
            case .missingOutroLogoImage:
                return "Please select a store logo image for the static logo outro."
            case .missingOutroVideoURL:
                return "Please select an outro video file."
            case .exportSessionCreationFailed:
                return "Could not initialize AVAssetExportSession for the composed Reel."
            case .exportFailed(let error):
                return "Export failed: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }

    private struct ResolvedSegmentAsset {
        let planned: PlannedSegment
        let asset: AVURLAsset
        let videoTrack: AVAssetTrack
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        let compositionTrack: AVMutableCompositionTrack
        let startTime: CMTime
        let endTime: CMTime
    }

    private static let renderSize = CGSize(width: 1080, height: 1920)
    private static let timescale: CMTimeScale = 600

    static func compose(
        request: ReelCompositionRequest,
        statusHandler: @MainActor @Sendable (String) -> Void
    ) async throws -> URL {
        guard !request.items.isEmpty else {
            throw ComposerError.noMediaSelected
        }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-compose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        // 1. Build clip specs using actual durations for video items.
        await statusHandler("Analyzing selected clips...")
        var clipSpecs: [MediaClipSpec] = []
        var videoAssetsByID: [UUID: AVURLAsset] = [:]

        for item in request.items {
            switch item.kind {
            case .photo:
                clipSpecs.append(
                    MediaClipSpec(
                        id: item.id,
                        kind: .photo,
                        sourceDurationSeconds: request.polishSettings.defaultPhotoDuration
                    )
                )
            case .video:
                guard let videoURL = item.videoURL else {
                    throw ComposerError.missingVideoURL(item.displayTitle)
                }
                let asset = AVURLAsset(url: videoURL)
                let duration = try await asset.load(.duration)
                let durationSeconds = max(0.2, CMTimeGetSeconds(duration))
                videoAssetsByID[item.id] = asset
                clipSpecs.append(
                    MediaClipSpec(
                        id: item.id,
                        kind: .video,
                        sourceDurationSeconds: durationSeconds
                    )
                )
            }
        }

        var outroVideoAsset: AVURLAsset?
        let effectiveOutroMode: OutroSelectionMode
        switch request.outroMode {
        case .none:
            effectiveOutroMode = .none
        case .staticLogo(let hex, let duration):
            guard request.outroLogoImage != nil else {
                throw ComposerError.missingOutroLogoImage
            }
            effectiveOutroMode = .staticLogo(backgroundColorHex: hex, durationSeconds: duration)
        case .videoClip:
            guard let outroURL = request.outroVideoURL else {
                throw ComposerError.missingOutroVideoURL
            }
            let asset = AVURLAsset(url: outroURL)
            let duration = try await asset.load(.duration)
            outroVideoAsset = asset
            effectiveOutroMode = .videoClip(durationSeconds: max(0.2, CMTimeGetSeconds(duration)))
        }

        // 2. Detect beats if beat-sync is enabled with a custom audio track.
        var detectedBeats: [Double] = []
        if request.polishSettings.beatSyncEnabled,
           case .customTrack(let audioURL, _) = request.audioMode {
            await statusHandler("Detecting audio beats...")
            detectedBeats = (try? await AudioBeatDetector.detectBeats(in: audioURL)) ?? []
        }

        // 3. Plan timeline using ReelsCreatorCore.
        let timeline = TimelinePlanner.plan(
            clips: clipSpecs,
            audio: request.audioMode,
            outro: effectiveOutroMode,
            settings: request.polishSettings,
            beatTimestamps: detectedBeats
        )

        // 4. Build AVMutableComposition with two alternating video tracks for clean crossfades.
        let composition = AVMutableComposition()
        guard
            let videoTrackA = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let videoTrackB = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ComposerError.exportSessionCreationFailed
        }

        // Original clip audio uses two alternating tracks (mirroring video A/B) so crossfaded
        // clips never overlap on the same track. Inserting into the middle of a track would
        // shift existing media later and desync audio from video.
        var originalAudioTracks: [AVMutableCompositionTrack] = []
        if !timeline.muteOriginalVideoClips {
            for _ in 0..<2 {
                if let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                    originalAudioTracks.append(track)
                }
            }
        }

        var resolvedSegments: [ResolvedSegmentAsset] = []
        let itemsByID = Dictionary(uniqueKeysWithValues: request.items.map { ($0.id, $0) })

        for segment in timeline.segments {
            let segmentAsset: AVURLAsset
            let segmentTitle: String

            if segment.isOutro {
                switch effectiveOutroMode {
                case .none:
                    continue
                case .staticLogo:
                    guard let logoImage = request.outroLogoImage else {
                        throw ComposerError.missingOutroLogoImage
                    }
                    await statusHandler("Rendering store logo outro...")
                    let outroClipURL = workingDirectory.appendingPathComponent("outro-logo.mp4")
                    try await StillImageVideoGenerator.generateVideo(
                        from: logoImage,
                        durationSeconds: segment.durationSeconds,
                        layoutMode: .aspectFitCentered(backgroundColor: request.outroBackgroundColor),
                        outputURL: outroClipURL
                    )
                    segmentAsset = AVURLAsset(url: outroClipURL)
                    segmentTitle = "Store Logo Outro"
                case .videoClip:
                    guard let outroAsset = outroVideoAsset else {
                        throw ComposerError.missingOutroVideoURL
                    }
                    segmentAsset = outroAsset
                    segmentTitle = "Outro Video"
                }
            } else {
                guard let item = itemsByID[segment.id] else { continue }
                segmentTitle = item.displayTitle

                switch item.kind {
                case .photo:
                    guard let photoImage = item.photoImage else {
                        throw ComposerError.missingPhotoImage(item.displayTitle)
                    }
                    await statusHandler("Preparing photo \(segment.index + 1) of \(timeline.segments.count)...")
                    let photoClipURL = workingDirectory.appendingPathComponent("photo-\(segment.index).mp4")
                    try await StillImageVideoGenerator.generateVideo(
                        from: photoImage,
                        durationSeconds: segment.durationSeconds,
                        layoutMode: .aspectFillCrop,
                        outputURL: photoClipURL
                    )
                    segmentAsset = AVURLAsset(url: photoClipURL)
                case .video:
                    guard let cachedAsset = videoAssetsByID[item.id] else {
                        throw ComposerError.missingVideoURL(item.displayTitle)
                    }
                    segmentAsset = cachedAsset
                }
            }

            let videoTracks = try await segmentAsset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first else {
                throw ComposerError.missingVideoTrack(segmentTitle)
            }

            let assetDuration = try await segmentAsset.load(.duration)
            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

            let desiredDuration = CMTime(seconds: segment.durationSeconds, preferredTimescale: timescale)
            let clampedDuration = CMTimeMinimum(desiredDuration, assetDuration)
            guard clampedDuration > .zero else {
                throw ComposerError.missingVideoTrack(segmentTitle)
            }
            let sourceRange = CMTimeRange(start: .zero, duration: clampedDuration)
            let targetTrack = (segment.trackIndex == 0) ? videoTrackA : videoTrackB

            // Derive the insert time from the *actual* end of the previous clip (not the planned
            // Double timeline), so clamped/rounded durations never leave gaps or overlaps.
            var insertAt = CMTime.zero
            if let previous = resolvedSegments.last {
                let plannedOverlap = max(0, previous.planned.endTimeSeconds - segment.startTimeSeconds)
                let previousDuration = previous.endTime - previous.startTime
                let maxOverlap = CMTimeMultiplyByRatio(
                    CMTimeMinimum(previousDuration, clampedDuration),
                    multiplier: 1,
                    divisor: 2
                )
                let overlap = CMTimeMinimum(
                    CMTime(seconds: plannedOverlap, preferredTimescale: timescale),
                    maxOverlap
                )
                insertAt = previous.endTime - overlap
            }
            // Never insert before existing media on the same track (that would shift it later).
            insertAt = CMTimeMaximum(insertAt, trackEnd(targetTrack))

            try targetTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: insertAt)

            if segment.keepOriginalAudio, !originalAudioTracks.isEmpty {
                let audioTrack = originalAudioTracks[segment.trackIndex % originalAudioTracks.count]
                let audioTracks = try await segmentAsset.loadTracks(withMediaType: .audio)
                if let sourceAudioTrack = audioTracks.first, insertAt >= trackEnd(audioTrack) {
                    let audioDuration = try await segmentAsset.load(.duration)
                    let audioRange = CMTimeRange(
                        start: .zero,
                        duration: CMTimeMinimum(clampedDuration, audioDuration)
                    )
                    try? audioTrack.insertTimeRange(audioRange, of: sourceAudioTrack, at: insertAt)
                }
            }

            resolvedSegments.append(
                ResolvedSegmentAsset(
                    planned: segment,
                    asset: segmentAsset,
                    videoTrack: sourceVideoTrack,
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    compositionTrack: targetTrack,
                    startTime: insertAt,
                    endTime: CMTimeAdd(insertAt, clampedDuration)
                )
            )
        }

        guard let videoEnd = resolvedSegments.map(\.endTime).max(), videoEnd > .zero else {
            throw ComposerError.noMediaSelected
        }

        // 5. Add custom background audio (and fade out over final 0.5s) if selected.
        var audioMix: AVMutableAudioMix?
        if case .customTrack(let audioURL, _) = request.audioMode {
            let bgAudioAsset = AVURLAsset(url: audioURL)
            let bgAudioTracks = try await bgAudioAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = bgAudioTracks.first,
               let compAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let bgAssetDuration = try await bgAudioAsset.load(.duration)
                let insertedAudioDuration = CMTimeMinimum(bgAssetDuration, videoEnd)
                if CMTimeGetSeconds(insertedAudioDuration) > 0.05 {
                    try compAudioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: insertedAudioDuration),
                        of: sourceAudioTrack,
                        at: .zero
                    )

                    let totalSeconds = CMTimeGetSeconds(insertedAudioDuration)
                    if totalSeconds > 0.8 {
                        let fadeStart = CMTime(seconds: totalSeconds - 0.5, preferredTimescale: timescale)
                        let fadeDuration = CMTime(seconds: 0.5, preferredTimescale: timescale)
                        let params = AVMutableAudioMixInputParameters(track: compAudioTrack)
                        params.setVolumeRamp(
                            fromStartVolume: 1.0,
                            toEndVolume: 0.0,
                            timeRange: CMTimeRange(start: fadeStart, duration: fadeDuration)
                        )
                        let mix = AVMutableAudioMix()
                        mix.inputParameters = [params]
                        audioMix = mix
                    }
                }
            }
        }

        // 6. Sanitize the composition: no track may extend past the last video frame (otherwise
        // the video composition instructions don't cover the full duration and export fails with
        // err -16976), and empty tracks are removed.
        for track in composition.tracks {
            let end = trackEnd(track)
            if end > videoEnd {
                track.removeTimeRange(CMTimeRange(start: videoEnd, end: end))
            }
        }
        for track in composition.tracks where track.segments.isEmpty {
            composition.removeTrack(track)
        }

        // 7. Build 1080x1920 video composition instructions with crossfades.
        await statusHandler("Encoding 9:16 Reel...")
        let videoComposition = buildVideoComposition(for: resolvedSegments, totalDuration: videoEnd)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reel-\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ComposerError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        exportSession.shouldOptimizeForNetworkUse = true

        if #available(iOS 18.0, *) {
            do {
                try await exportSession.export(to: outputURL, as: .mp4)
            } catch {
                throw ComposerError.exportFailed(error)
            }
        } else {
            await exportSession.export()
            if exportSession.status != .completed {
                throw ComposerError.exportFailed(exportSession.error)
            }
        }

        try? FileManager.default.removeItem(at: workingDirectory)
        return outputURL
    }

    private static func trackEnd(_ track: AVMutableCompositionTrack) -> CMTime {
        track.segments.last?.timeMapping.target.end ?? .zero
    }

    /// Builds instructions that tile `[0, totalDuration]` contiguously with no gaps — a hard
    /// requirement of AVVideoComposition (violations fail export with err -16976).
    private static func buildVideoComposition(
        for segments: [ResolvedSegmentAsset],
        totalDuration: CMTime
    ) -> AVMutableVideoComposition {
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        var rawBoundaries: [CMTime] = [.zero, totalDuration]
        for seg in segments {
            rawBoundaries.append(seg.startTime)
            rawBoundaries.append(seg.endTime)
        }

        let tolerance = CMTime(value: 1, timescale: timescale)
        var sortedBoundaries = rawBoundaries
            .filter { $0 >= .zero && $0 <= totalDuration }
            .sorted()
            .reduce(into: [CMTime]()) { unique, time in
                if let last = unique.last, time - last <= tolerance {
                    return
                }
                unique.append(time)
            }
        // Guarantee the final boundary is exactly the composition end.
        if sortedBoundaries.count >= 2 {
            sortedBoundaries[sortedBoundaries.count - 1] = totalDuration
        } else {
            sortedBoundaries = [.zero, totalDuration]
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []

        for idx in 0..<(sortedBoundaries.count - 1) {
            let sliceStart = sortedBoundaries[idx]
            let sliceEnd = sortedBoundaries[idx + 1]
            let sliceDuration = CMTimeSubtract(sliceEnd, sliceStart)
            guard sliceDuration > .zero else { continue }

            let sliceMid = CMTimeAdd(sliceStart, CMTimeMultiplyByFloat64(sliceDuration, multiplier: 0.5))
            var activeSegments = segments
                .filter { seg in
                    CMTimeCompare(seg.startTime, sliceMid) <= 0 && CMTimeCompare(seg.endTime, sliceMid) > 0
                }
                .sorted { $0.planned.index < $1.planned.index }

            // Never leave a gap: fall back to the closest preceding (or first) segment.
            if activeSegments.isEmpty {
                if let fallback = segments.last(where: { $0.startTime <= sliceMid }) ?? segments.first {
                    activeSegments = [fallback]
                } else {
                    continue
                }
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: sliceStart, duration: sliceDuration)

            if activeSegments.count == 1, let active = activeSegments.first {
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: active.compositionTrack)
                let transform = aspectFillTransform(
                    naturalSize: active.naturalSize,
                    preferredTransform: active.preferredTransform,
                    renderSize: renderSize
                )
                layer.setTransform(transform, at: sliceStart)
                layer.setOpacity(1.0, at: sliceStart)
                instruction.layerInstructions = [layer]
            } else {
                // Place the newest incoming segment on top (index 0) ramping 0 -> 1 over outgoing (1.0).
                let incoming = activeSegments.last!
                let outgoing = activeSegments[activeSegments.count - 2]

                let incomingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: incoming.compositionTrack)
                let incomingTransform = aspectFillTransform(
                    naturalSize: incoming.naturalSize,
                    preferredTransform: incoming.preferredTransform,
                    renderSize: renderSize
                )
                incomingLayer.setTransform(incomingTransform, at: sliceStart)
                incomingLayer.setOpacityRamp(
                    fromStartOpacity: 0.0,
                    toEndOpacity: 1.0,
                    timeRange: instruction.timeRange
                )

                let outgoingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: outgoing.compositionTrack)
                let outgoingTransform = aspectFillTransform(
                    naturalSize: outgoing.naturalSize,
                    preferredTransform: outgoing.preferredTransform,
                    renderSize: renderSize
                )
                outgoingLayer.setTransform(outgoingTransform, at: sliceStart)
                outgoingLayer.setOpacity(1.0, at: sliceStart)

                instruction.layerInstructions = [incomingLayer, outgoingLayer]
            }

            instructions.append(instruction)
        }

        videoComposition.instructions = instructions
        return videoComposition
    }

    private static func aspectFillTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedWidth = abs(transformedRect.width)
        let orientedHeight = abs(transformedRect.height)

        guard orientedWidth > 0, orientedHeight > 0 else {
            return preferredTransform
        }

        let normalize = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.origin.x, y: -transformedRect.origin.y)
        )
        let scale = max(renderSize.width / orientedWidth, renderSize.height / orientedHeight)
        let scaledWidth = orientedWidth * scale
        let scaledHeight = orientedHeight * scale
        let offsetX = (renderSize.width - scaledWidth) / 2.0
        let offsetY = (renderSize.height - scaledHeight) / 2.0

        return normalize
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}
