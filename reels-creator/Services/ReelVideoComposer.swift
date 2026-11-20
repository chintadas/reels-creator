import AVFoundation
import Foundation
import QuartzCore
import ReelsCreatorCore
import UIKit

struct ReelCompositionRequest: @unchecked Sendable {
    let items: [SelectedMediaItem]
    let audioMode: AudioSelectionMode
    let outroMode: OutroSelectionMode
    let outroLogoImage: UIImage?
    let outroVideoURL: URL?
    let polishSettings: ReelPolishSettings
    let introOverlay: IntroTextOverlaySpec?

    init(
        items: [SelectedMediaItem],
        audioMode: AudioSelectionMode,
        outroMode: OutroSelectionMode,
        outroLogoImage: UIImage?,
        outroVideoURL: URL?,
        polishSettings: ReelPolishSettings,
        introOverlay: IntroTextOverlaySpec? = nil
    ) {
        self.items = items
        self.audioMode = audioMode
        self.outroMode = outroMode
        self.outroLogoImage = outroLogoImage
        self.outroVideoURL = outroVideoURL
        self.polishSettings = polishSettings
        self.introOverlay = introOverlay
    }
}

enum ReelVideoComposer {
    enum ComposerError: LocalizedError {
        case noMediaSelected
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
            case .missingVideoURL(let title):
                return "Could not locate video file for \(title)."
            case .missingVideoTrack(let title):
                return "The clip \"\(title)\" does not contain a valid video track."
            case .missingOutroLogoImage:
                return "Please select a store logo image for the logo overlay outro."
            case .missingOutroVideoURL:
                return "Please select an outro video file."
            case .exportSessionCreationFailed:
                return "Could not initialize AVAssetExportSession for the composed Reel."
            case .exportFailed(let error):
                return "Export failed: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }

    private struct PreparedInputs {
        let clipSpecs: [MediaClipSpec]
        let videoAssetsByID: [UUID: AVURLAsset]
        let outroVideoAsset: AVURLAsset?
        let effectiveOutroMode: OutroSelectionMode
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

    static func compose(
        request: ReelCompositionRequest,
        statusHandler: @MainActor @Sendable (String) -> Void
    ) async throws -> URL {
        guard !request.items.isEmpty else {
            throw ComposerError.noMediaSelected
        }

        let workingDirectory = try TemporaryMediaStore.makeTemporaryDirectory(prefix: "reel-compose")
        defer { TemporaryMediaStore.removeItemIfPresent(workingDirectory) }

        await statusHandler("Analyzing selected clips...")
        let prepared = try await prepareInputs(request: request)

        var detectedBeats: [Double] = []
        if request.polishSettings.beatSyncEnabled,
           case .customTrack(let audioURL, _) = request.audioMode {
            await statusHandler("Detecting audio beats...")
            detectedBeats = (try? await AudioBeatDetector.detectBeats(in: audioURL)) ?? []
        }

        let timeline = TimelinePlanner.plan(
            clips: prepared.clipSpecs,
            audio: request.audioMode,
            outro: prepared.effectiveOutroMode,
            settings: request.polishSettings,
            beatTimestamps: detectedBeats,
            introOverlay: request.introOverlay
        )

        let composition = AVMutableComposition()
        let resolvedSegments = try await assembleComposition(
            composition: composition,
            timeline: timeline,
            request: request,
            prepared: prepared,
            workingDirectory: workingDirectory,
            statusHandler: statusHandler
        )

        guard let videoEnd = resolvedSegments.map(\.endTime).max(), videoEnd > .zero else {
            throw ComposerError.noMediaSelected
        }

        let audioMix = try await attachBackgroundAudio(
            to: composition,
            audioMode: request.audioMode,
            videoEnd: videoEnd
        )

        sanitizeTracks(in: composition, videoEnd: videoEnd)

        await statusHandler("Encoding 9:16 Reel...")
        let videoComposition = buildVideoComposition(for: resolvedSegments, totalDuration: videoEnd)
        attachOverlays(
            to: videoComposition,
            request: request,
            effectiveOutroMode: prepared.effectiveOutroMode,
            resolvedSegments: resolvedSegments,
            videoEnd: videoEnd
        )

        return try await export(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }

    // MARK: - Pipeline Stages

    private static func prepareInputs(request: ReelCompositionRequest) async throws -> PreparedInputs {
        var clipSpecs: [MediaClipSpec] = []
        clipSpecs.reserveCapacity(request.items.count)
        var videoAssetsByID: [UUID: AVURLAsset] = [:]

        for item in request.items {
            switch item.kind {
            case .photo:
                clipSpecs.append(MediaClipSpec(id: item.id, kind: .photo))
            case .video:
                let asset = AVURLAsset(url: item.mediaURL)
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
        case .logoOverlay(let duration, let fadeIn):
            guard request.outroLogoImage != nil else {
                throw ComposerError.missingOutroLogoImage
            }
            effectiveOutroMode = .logoOverlay(durationSeconds: duration, fadeInDurationSeconds: fadeIn)
        case .videoClip:
            guard let outroURL = request.outroVideoURL else {
                throw ComposerError.missingOutroVideoURL
            }
            let asset = AVURLAsset(url: outroURL)
            let duration = try await asset.load(.duration)
            outroVideoAsset = asset
            effectiveOutroMode = .videoClip(durationSeconds: max(0.2, CMTimeGetSeconds(duration)))
        }

        return PreparedInputs(
            clipSpecs: clipSpecs,
            videoAssetsByID: videoAssetsByID,
            outroVideoAsset: outroVideoAsset,
            effectiveOutroMode: effectiveOutroMode
        )
    }

    private static func assembleComposition(
        composition: AVMutableComposition,
        timeline: PlannedTimeline,
        request: ReelCompositionRequest,
        prepared: PreparedInputs,
        workingDirectory: URL,
        statusHandler: @MainActor @Sendable (String) -> Void
    ) async throws -> [ResolvedSegmentAsset] {
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
        let timescale = ReelRenderConfig.timescale

        for segment in timeline.segments {
            let segmentAsset: AVURLAsset
            let segmentTitle: String

            if segment.isOutro {
                switch prepared.effectiveOutroMode {
                case .none, .logoOverlay:
                    continue
                case .videoClip:
                    guard let outroAsset = prepared.outroVideoAsset else {
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
                    await statusHandler("Preparing photo \(segment.index + 1) of \(timeline.segments.count)...")
                    let photoClipURL = workingDirectory.appendingPathComponent("photo-\(segment.index).mp4")
                    try await StillImageVideoGenerator.generateVideo(
                        fromImageAt: item.mediaURL,
                        durationSeconds: segment.durationSeconds,
                        outputURL: photoClipURL
                    )
                    segmentAsset = AVURLAsset(url: photoClipURL)
                case .video:
                    guard let cachedAsset = prepared.videoAssetsByID[item.id] else {
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
                    let audioTimeRange = try await sourceAudioTrack.load(.timeRange)
                    let audioDuration = (audioTimeRange.duration.isValid && !audioTimeRange.duration.isIndefinite && audioTimeRange.duration > .zero)
                        ? audioTimeRange.duration
                        : assetDuration
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

        return resolvedSegments
    }

    private static func attachBackgroundAudio(
        to composition: AVMutableComposition,
        audioMode: AudioSelectionMode,
        videoEnd: CMTime
    ) async throws -> AVMutableAudioMix? {
        guard case .customTrack(let audioURL, _) = audioMode else {
            return nil
        }

        let timescale = ReelRenderConfig.timescale
        let bgAudioAsset = AVURLAsset(url: audioURL)
        let bgAudioTracks = try await bgAudioAsset.loadTracks(withMediaType: .audio)
        guard let sourceAudioTrack = bgAudioTracks.first,
              let compAudioTrack = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }

        let bgAssetDuration = try await bgAudioAsset.load(.duration)
        let insertedAudioDuration = CMTimeMinimum(bgAssetDuration, videoEnd)
        guard CMTimeGetSeconds(insertedAudioDuration) > 0.05 else {
            return nil
        }

        try compAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: insertedAudioDuration),
            of: sourceAudioTrack,
            at: .zero
        )

        let totalSeconds = CMTimeGetSeconds(insertedAudioDuration)
        guard totalSeconds > 0.8 else {
            return nil
        }

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
        return mix
    }

    /// Ensures no track extends past `videoEnd` (which causes export failure err -16976)
    /// and removes any tracks with zero segments.
    private static func sanitizeTracks(in composition: AVMutableComposition, videoEnd: CMTime) {
        for track in composition.tracks {
            let end = trackEnd(track)
            if end > videoEnd {
                track.removeTimeRange(CMTimeRange(start: videoEnd, end: end))
            }
        }
        for track in composition.tracks where track.segments.isEmpty {
            composition.removeTrack(track)
        }
    }

    private static func attachOverlays(
        to videoComposition: AVMutableVideoComposition,
        request: ReelCompositionRequest,
        effectiveOutroMode: OutroSelectionMode,
        resolvedSegments: [ResolvedSegmentAsset],
        videoEnd: CMTime
    ) {
        let actualTotalSeconds = CMTimeGetSeconds(videoEnd)
        let outroVideoStart = resolvedSegments
            .first(where: { $0.planned.isOutro })
            .map { CMTimeGetSeconds($0.startTime) }

        let overlays = TimelinePlanner.resolveOverlays(
            intro: request.introOverlay,
            outro: effectiveOutroMode,
            outroVideoStartTimeSeconds: outroVideoStart,
            totalDurationSeconds: actualTotalSeconds
        )

        var overlayLayers: [CALayer] = []
        if let introOverlay = overlays.introOverlay,
           let introLayer = IntroTextOverlayRenderer.makeOverlayLayer(
               for: introOverlay,
               renderSize: ReelRenderConfig.renderSize
           ) {
            overlayLayers.append(introLayer)
        }

        if let outroLogoOverlay = overlays.outroLogoOverlay,
           let logoImage = request.outroLogoImage,
           let outroLogoLayer = OutroLogoOverlayRenderer.makeOverlayLayer(
               logo: logoImage,
               overlay: outroLogoOverlay,
               renderSize: ReelRenderConfig.renderSize
           ) {
            overlayLayers.append(outroLogoLayer)
        }

        if let animationTool = OverlayCompositionBuilder.makeAnimationTool(
            overlayLayers: overlayLayers,
            renderSize: ReelRenderConfig.renderSize
        ) {
            videoComposition.animationTool = animationTool
        }
    }

    private static func export(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        audioMix: AVMutableAudioMix?
    ) async throws -> URL {
        let outputURL = TemporaryMediaStore.makeTemporaryURL(prefix: "reel", fileExtension: "mp4")
        TemporaryMediaStore.removeItemIfPresent(outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ComposerError.exportSessionCreationFailed
        }

        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            try await exportSession.exportCompat(to: outputURL, as: .mp4)
            return outputURL
        } catch {
            TemporaryMediaStore.removeItemIfPresent(outputURL)
            throw ComposerError.exportFailed(error)
        }
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
        let renderSize = ReelRenderConfig.renderSize
        let timescale = ReelRenderConfig.timescale

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = ReelRenderConfig.frameDuration

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
