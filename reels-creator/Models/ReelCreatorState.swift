import Foundation
import PhotosUI
import SwiftUI
import UIKit

enum AudioSourceChoice: String, CaseIterable, Identifiable {
    case instagramAudio = "No Music (Add in IG)"
    case customTrack = "Custom Audio Track"

    var id: String { rawValue }
}

enum OutroTypeChoice: String, CaseIterable, Identifiable {
    case none = "None"
    case logoOverlay = "Logo Overlay"
    case videoClip = "Outro Video"

    var id: String { rawValue }
}

struct CustomAudioTrack: Equatable, @unchecked Sendable {
    let url: URL
    let name: String
    let durationSeconds: Double
    let thumbnail: UIImage?

    static func == (lhs: CustomAudioTrack, rhs: CustomAudioTrack) -> Bool {
        lhs.url == rhs.url
            && lhs.name == rhs.name
            && lhs.durationSeconds == rhs.durationSeconds
    }
}

struct OutroVideoClip: Equatable, Sendable {
    let url: URL
    let name: String
    let durationSeconds: Double
}

enum PhotoSaveState: Equatable, Sendable {
    case idle
    case saving
    case saved
}

struct ExportResultState: Equatable, Sendable {
    let videoURL: URL
    var saveState: PhotoSaveState = .idle
}

struct ReelCreatorDependencies: Sendable {
    var loadMediaItem: @Sendable (PhotosPickerItem, Double, Int) async throws -> SelectedMediaItem?
    var extractCustomAudio: @Sendable (PhotosPickerItem) async throws -> CustomAudioTrack
    var loadLogoImage: @Sendable (PhotosPickerItem) async throws -> UIImage?
    var importLogoImage: @Sendable (URL) async throws -> UIImage
    var loadOutroVideo: @Sendable (PhotosPickerItem) async throws -> OutroVideoClip?
    var importOutroVideo: @Sendable (URL) async throws -> OutroVideoClip
    var composeReel: @Sendable (ReelCompositionRequest, @escaping @MainActor @Sendable (String) -> Void) async throws -> URL
    var saveVideoToPhotos: @Sendable (URL) async throws -> Void
    var removeTemporaryFile: @Sendable (URL?) -> Void

    static let live = ReelCreatorDependencies(
        loadMediaItem: { item, defaultPhotoDuration, displayIndex in
            try await MediaImportService.loadMediaItem(
                from: item,
                defaultPhotoDuration: defaultPhotoDuration,
                displayIndex: displayIndex
            )
        },
        extractCustomAudio: { item in
            try await MediaImportService.extractCustomAudio(from: item)
        },
        loadLogoImage: { item in
            try await MediaImportService.loadLogoImage(from: item)
        },
        importLogoImage: { url in
            try await MediaImportService.importLogoImage(from: url)
        },
        loadOutroVideo: { item in
            try await MediaImportService.loadOutroVideo(from: item)
        },
        importOutroVideo: { url in
            try await MediaImportService.importOutroVideo(from: url)
        },
        composeReel: { request, statusHandler in
            try await ReelVideoComposer.compose(request: request, statusHandler: statusHandler)
        },
        saveVideoToPhotos: { url in
            try await PhotoLibrarySaver.saveVideo(at: url)
        },
        removeTemporaryFile: { url in
            TemporaryMediaStore.removeIfTemporary(url)
        }
    )
}
