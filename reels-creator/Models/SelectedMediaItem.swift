import AVFoundation
import Foundation
import PhotosUI
import ReelsCreatorCore
import SwiftUI
import UniformTypeIdentifiers

struct MovieFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-video-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

struct SelectedMediaItem: Identifiable, Equatable {
    let id: UUID
    let kind: MediaClipKind
    let thumbnail: UIImage
    let photoImage: UIImage?
    let videoURL: URL?
    var durationSeconds: Double
    let displayTitle: String

    init(
        id: UUID = UUID(),
        kind: MediaClipKind,
        thumbnail: UIImage,
        photoImage: UIImage? = nil,
        videoURL: URL? = nil,
        durationSeconds: Double,
        displayTitle: String
    ) {
        self.id = id
        self.kind = kind
        self.thumbnail = thumbnail
        self.photoImage = photoImage
        self.videoURL = videoURL
        self.durationSeconds = durationSeconds
        self.displayTitle = displayTitle
    }

    static func == (lhs: SelectedMediaItem, rhs: SelectedMediaItem) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.videoURL == rhs.videoURL
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.displayTitle == rhs.displayTitle
    }

    static func generateVideoThumbnail(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 640)

        do {
            let result = try await generator.image(at: .zero)
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }
}
