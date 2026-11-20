import AVFoundation
import Foundation
import ImageIO
import PhotosUI
import ReelsCreatorCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum MediaImportService {
    enum ImportError: LocalizedError {
        case missingVideoAsset
        case unsupportedImage

        var errorDescription: String? {
            switch self {
            case .missingVideoAsset:
                return "Could not load the selected video from Photos."
            case .unsupportedImage:
                return "The selected file is not a supported image."
            }
        }
    }

    static func loadMediaItem(
        from pickerItem: PhotosPickerItem,
        defaultPhotoDuration: Double,
        displayIndex: Int
    ) async throws -> SelectedMediaItem? {
        let isMovie = pickerItem.supportedContentTypes.contains { $0.conforms(to: .movie) }

        if isMovie {
            guard let movie = try await pickerItem.loadTransferable(type: MovieFileTransferable.self) else {
                return nil
            }
            do {
                let asset = AVURLAsset(url: movie.url)
                let duration = try await asset.load(.duration)
                let durationSeconds = max(0.2, CMTimeGetSeconds(duration))
                let thumbnail = await generateVideoThumbnail(url: movie.url)
                    ?? UIImage(systemName: "video.fill")
                    ?? UIImage()

                return SelectedMediaItem(
                    kind: .video,
                    thumbnail: thumbnail,
                    mediaURL: movie.url,
                    durationSeconds: durationSeconds,
                    displayTitle: "Video \(displayIndex)"
                )
            } catch {
                TemporaryMediaStore.removeIfTemporary(movie.url)
                throw error
            }
        } else {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                return nil
            }
            let fileExt = pickerItem.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"

            return try await Task.detached(priority: .userInitiated) {
                guard let thumbnail = createPhotoThumbnail(from: data) else {
                    return nil
                }
                let fileURL = try TemporaryMediaStore.writeData(
                    data,
                    prefix: "picked-photo",
                    fileExtension: fileExt
                )
                return SelectedMediaItem(
                    kind: .photo,
                    thumbnail: thumbnail,
                    mediaURL: fileURL,
                    durationSeconds: defaultPhotoDuration,
                    displayTitle: "Photo \(displayIndex)"
                )
            }.value
        }
    }

    static func extractCustomAudio(from item: PhotosPickerItem) async throws -> CustomAudioTrack {
        guard let movie = try await item.loadTransferable(type: MovieFileTransferable.self) else {
            throw ImportError.missingVideoAsset
        }
        defer { TemporaryMediaStore.removeIfTemporary(movie.url) }

        let extracted = try await VideoAudioExtractor.extractAudio(from: movie.url)
        let thumbnail = await generateVideoThumbnail(url: movie.url)

        return CustomAudioTrack(
            url: extracted.audioURL,
            name: "Audio from Video",
            durationSeconds: extracted.durationSeconds,
            thumbnail: thumbnail
        )
    }

    static func loadLogoImage(from item: PhotosPickerItem) async throws -> UIImage? {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            return nil
        }
        return await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
    }

    static func importLogoImage(from securityScopedURL: URL) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let localURL = try TemporaryMediaStore.copySecurityScopedFile(from: securityScopedURL, prefix: "logo")
            defer { TemporaryMediaStore.removeIfTemporary(localURL) }
            let data = try Data(contentsOf: localURL)
            guard let image = UIImage(data: data) else {
                throw ImportError.unsupportedImage
            }
            return image
        }.value
    }

    static func loadOutroVideo(from item: PhotosPickerItem) async throws -> OutroVideoClip? {
        guard let movie = try await item.loadTransferable(type: MovieFileTransferable.self) else {
            return nil
        }
        do {
            let asset = AVURLAsset(url: movie.url)
            let duration = try await asset.load(.duration)
            return OutroVideoClip(
                url: movie.url,
                name: "Selected Outro Video",
                durationSeconds: max(0.2, CMTimeGetSeconds(duration))
            )
        } catch {
            TemporaryMediaStore.removeIfTemporary(movie.url)
            throw error
        }
    }

    static func importOutroVideo(from securityScopedURL: URL) async throws -> OutroVideoClip {
        let localURL = try await Task.detached(priority: .userInitiated) {
            try TemporaryMediaStore.copySecurityScopedFile(from: securityScopedURL, prefix: "outro")
        }.value

        do {
            let asset = AVURLAsset(url: localURL)
            let duration = try await asset.load(.duration)
            return OutroVideoClip(
                url: localURL,
                name: securityScopedURL.lastPathComponent,
                durationSeconds: max(0.2, CMTimeGetSeconds(duration))
            )
        } catch {
            TemporaryMediaStore.removeIfTemporary(localURL)
            throw error
        }
    }

    static func generateVideoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = ReelRenderConfig.videoThumbnailMaxSize

        do {
            let result = try await generator.image(at: .zero)
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }

    private static func createPhotoThumbnail(from data: Data) -> UIImage? {
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: ReelRenderConfig.photoThumbnailMaxPixelSize
            ]
            if let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                return UIImage(cgImage: cgThumbnail)
            }
        }
        return UIImage(data: data)
    }
}
