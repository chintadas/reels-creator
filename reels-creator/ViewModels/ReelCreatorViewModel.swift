import AVFoundation
import Foundation
import Observation
import PhotosUI
import ReelsCreatorCore
import SwiftUI
import UIKit

enum AudioSourceChoice: String, CaseIterable, Identifiable {
    case instagramAudio = "No Music (Add in IG)"
    case customTrack = "Custom Audio Track"

    var id: String { rawValue }
}

enum OutroTypeChoice: String, CaseIterable, Identifiable {
    case none = "None"
    case staticLogo = "Static Logo"
    case videoClip = "Outro Video"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ReelCreatorViewModel {
    var selectedItems: [SelectedMediaItem] = []
    var isLoadingMedia = false

    var audioChoice: AudioSourceChoice = .instagramAudio
    var customAudioURL: URL?
    var customAudioName: String?
    var customAudioDurationSeconds: Double = 0
    var customAudioThumbnail: UIImage?
    var isExtractingAudio = false

    var outroType: OutroTypeChoice = .staticLogo
    var logoImage: UIImage?
    var outroBackgroundColor: Color = .black
    var outroDurationSeconds: Double = 2.0
    var outroVideoURL: URL?
    var outroVideoName: String?
    var outroVideoDurationSeconds: Double = 0

    var polishSettings = ReelPolishSettings()
    var introText: String = ""

    var resolvedIntroOverlaySpec: IntroTextOverlaySpec? {
        IntroTextOverlaySpec(rawText: introText)
    }

    var isExporting = false
    var exportProgressMessage = ""
    var exportedVideoURL: URL?
    var showExportSheet = false
    var errorMessage: String?

    var isSavingToPhotos = false
    var savedToPhotosSuccess = false

    var canGenerateReel: Bool {
        guard !selectedItems.isEmpty, !isExporting, !isExtractingAudio else { return false }
        if audioChoice == .customTrack && customAudioURL == nil {
            return false
        }
        switch outroType {
        case .none:
            return true
        case .staticLogo:
            return logoImage != nil
        case .videoClip:
            return outroVideoURL != nil
        }
    }

    var validationHint: String? {
        if selectedItems.isEmpty {
            return "Select at least one photo or video to create a Reel."
        }
        if isExtractingAudio {
            return "Extracting audio from selected video..."
        }
        if audioChoice == .customTrack && customAudioURL == nil {
            return "Extract audio from a video or switch back to No Music (Add in IG)."
        }
        if outroType == .staticLogo && logoImage == nil {
            return "Pick your store logo image (PNG) or set Outro to None."
        }
        if outroType == .videoClip && outroVideoURL == nil {
            return "Pick a pre-made outro video clip or set Outro to None."
        }
        return nil
    }

    var estimatedDurationSeconds: Double {
        let specs = selectedItems.map { item in
            MediaClipSpec(
                id: item.id,
                kind: item.kind,
                sourceDurationSeconds: item.kind == .photo ? polishSettings.defaultPhotoDuration : item.durationSeconds
            )
        }
        let timeline = TimelinePlanner.plan(
            clips: specs,
            audio: resolvedAudioMode(),
            outro: resolvedOutroMode(),
            settings: polishSettings,
            introOverlay: resolvedIntroOverlaySpec
        )
        return timeline.totalDurationSeconds
    }

    func loadSelectedPickerItems(_ pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false }

        for pickerItem in pickerItems {
            do {
                let isMovie = pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }

                if isMovie, let movie = try await pickerItem.loadTransferable(type: MovieFileTransferable.self) {
                    let asset = AVURLAsset(url: movie.url)
                    let duration = try await asset.load(.duration)
                    let durationSeconds = max(0.2, CMTimeGetSeconds(duration))
                    let thumbnail = await SelectedMediaItem.generateVideoThumbnail(url: movie.url)
                        ?? UIImage(systemName: "video.fill")
                        ?? UIImage()

                    selectedItems.append(
                        SelectedMediaItem(
                            kind: .video,
                            thumbnail: thumbnail,
                            videoURL: movie.url,
                            durationSeconds: durationSeconds,
                            displayTitle: "Video \(selectedItems.count + 1)"
                        )
                    )
                } else if let data = try await pickerItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) {
                    // TODO: Move full-res photo decoding and thumbnail downscaling off @MainActor
                    // (e.g., via CGImageSourceCreateThumbnailAtIndex in a background task) to avoid main-thread I/O hangs.
                    let thumbnail = downscaledThumbnail(from: image)
                    selectedItems.append(
                        SelectedMediaItem(
                            kind: .photo,
                            thumbnail: thumbnail,
                            photoImage: image,
                            durationSeconds: polishSettings.defaultPhotoDuration,
                            displayTitle: "Photo \(selectedItems.count + 1)"
                        )
                    )
                }
            } catch {
                errorMessage = "Could not load one of the selected items: \(error.localizedDescription)"
            }
        }
    }

    func moveItemLeft(id: UUID) {
        guard let index = selectedItems.firstIndex(where: { $0.id == id }), index > 0 else { return }
        selectedItems.swapAt(index, index - 1)
    }

    func moveItemRight(id: UUID) {
        guard let index = selectedItems.firstIndex(where: { $0.id == id }),
              index < selectedItems.count - 1 else { return }
        selectedItems.swapAt(index, index + 1)
    }

    func removeItem(id: UUID) {
        selectedItems.removeAll { $0.id == id }
    }

    func clearAllItems() {
        selectedItems.removeAll()
    }

    func clearIntroText() {
        introText = ""
    }

    func extractAudioFromVideoItem(_ item: PhotosPickerItem?) async {
        guard let item, !isExtractingAudio else { return }
        isExtractingAudio = true
        defer { isExtractingAudio = false }

        do {
            guard let movie = try await item.loadTransferable(type: MovieFileTransferable.self) else {
                errorMessage = "Could not load the selected video from Photos."
                return
            }
            defer { removeTemporaryFileIfPresent(at: movie.url) }

            let extracted = try await VideoAudioExtractor.extractAudio(from: movie.url)
            let thumbnail = await SelectedMediaItem.generateVideoThumbnail(url: movie.url)

            let previousAudioURL = customAudioURL
            customAudioURL = extracted.audioURL
            customAudioName = "Audio from Video"
            customAudioDurationSeconds = extracted.durationSeconds
            customAudioThumbnail = thumbnail
            audioChoice = .customTrack
            removeTemporaryFileIfPresent(at: previousAudioURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCustomAudio() {
        removeTemporaryFileIfPresent(at: customAudioURL)
        customAudioURL = nil
        customAudioName = nil
        customAudioDurationSeconds = 0
        customAudioThumbnail = nil
        audioChoice = .instagramAudio
        polishSettings.beatSyncEnabled = false
    }

    func loadLogoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                logoImage = image
                outroType = .staticLogo
            }
        } catch {
            errorMessage = "Could not load logo image: \(error.localizedDescription)"
        }
    }

    func importLogoFile(url: URL) {
        do {
            let localURL = try copySecurityScopedFileToTemp(url: url, prefix: "logo")
            let data = try Data(contentsOf: localURL)
            if let image = UIImage(data: data) {
                logoImage = image
                outroType = .staticLogo
            } else {
                errorMessage = "The selected file is not a supported image."
            }
        } catch {
            errorMessage = "Could not import logo file: \(error.localizedDescription)"
        }
    }

    func importOutroVideo(url: URL) async {
        do {
            let localURL = try copySecurityScopedFileToTemp(url: url, prefix: "outro")
            let asset = AVURLAsset(url: localURL)
            let duration = try await asset.load(.duration)
            let seconds = max(0.2, CMTimeGetSeconds(duration))

            outroVideoURL = localURL
            outroVideoName = url.lastPathComponent
            outroVideoDurationSeconds = seconds
            outroType = .videoClip
        } catch {
            errorMessage = "Could not import outro video: \(error.localizedDescription)"
        }
    }

    func loadOutroVideoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let movie = try await item.loadTransferable(type: MovieFileTransferable.self) {
                let asset = AVURLAsset(url: movie.url)
                let duration = try await asset.load(.duration)
                outroVideoURL = movie.url
                outroVideoName = "Selected Outro Video"
                outroVideoDurationSeconds = max(0.2, CMTimeGetSeconds(duration))
                outroType = .videoClip
            }
        } catch {
            errorMessage = "Could not load outro video from Photos: \(error.localizedDescription)"
        }
    }

    func generateReel() async {
        guard canGenerateReel else { return }
        isExporting = true
        exportProgressMessage = "Preparing composition..."
        errorMessage = nil
        savedToPhotosSuccess = false

        defer {
            isExporting = false
            exportProgressMessage = ""
        }

        let request = ReelCompositionRequest(
            items: selectedItems,
            audioMode: resolvedAudioMode(),
            outroMode: resolvedOutroMode(),
            outroLogoImage: logoImage,
            outroBackgroundColor: UIColor(outroBackgroundColor),
            outroVideoURL: outroVideoURL,
            polishSettings: polishSettings,
            introOverlay: resolvedIntroOverlaySpec
        )

        do {
            let outputURL = try await ReelVideoComposer.compose(request: request) { [weak self] status in
                self?.exportProgressMessage = status
            }
            exportedVideoURL = outputURL
            showExportSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveExportedReelToPhotos() async {
        guard let url = exportedVideoURL, !isSavingToPhotos else { return }
        isSavingToPhotos = true
        defer { isSavingToPhotos = false }

        do {
            try await PhotoLibrarySaver.saveVideo(at: url)
            savedToPhotosSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedAudioMode() -> AudioSelectionMode {
        switch audioChoice {
        case .instagramAudio:
            return .none
        case .customTrack:
            if let customAudioURL {
                return .customTrack(url: customAudioURL, durationSeconds: customAudioDurationSeconds)
            }
            return .none
        }
    }

    private func resolvedOutroMode() -> OutroSelectionMode {
        switch outroType {
        case .none:
            return .none
        case .staticLogo:
            return .staticLogo(
                backgroundColorHex: hexString(from: outroBackgroundColor),
                durationSeconds: outroDurationSeconds
            )
        case .videoClip:
            return .videoClip(durationSeconds: max(0.2, outroVideoDurationSeconds))
        }
    }

    private func copySecurityScopedFileToTemp(url: URL, prefix: String) throws -> URL {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension
        var destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        if !ext.isEmpty {
            destination = destination.appendingPathExtension(ext)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func removeTemporaryFileIfPresent(at url: URL?) {
        guard let url else { return }
        let tempPath = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(tempPath) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func downscaledThumbnail(from image: UIImage) -> UIImage {
        let targetSize = CGSize(width: 240, height: 426)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
            let w = image.size.width * scale
            let h = image.size.height * scale
            image.draw(in: CGRect(x: (targetSize.width - w) / 2, y: (targetSize.height - h) / 2, width: w, height: h))
        }
    }

    private func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }
}
