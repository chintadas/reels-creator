import Foundation
import ReelsCreatorCore
import SwiftUI
import UniformTypeIdentifiers

struct MovieFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = try TemporaryMediaStore.copyFile(
                from: received.file,
                prefix: "picked-video",
                defaultExtension: "mov"
            )
            return Self(url: destination)
        }
    }
}

struct SelectedMediaItem: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    let kind: MediaClipKind
    let thumbnail: UIImage
    let mediaURL: URL
    var durationSeconds: Double
    let displayTitle: String

    init(
        id: UUID = UUID(),
        kind: MediaClipKind,
        thumbnail: UIImage,
        mediaURL: URL,
        durationSeconds: Double,
        displayTitle: String
    ) {
        self.id = id
        self.kind = kind
        self.thumbnail = thumbnail
        self.mediaURL = mediaURL
        self.durationSeconds = durationSeconds
        self.displayTitle = displayTitle
    }

    static func == (lhs: SelectedMediaItem, rhs: SelectedMediaItem) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.mediaURL == rhs.mediaURL
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.displayTitle == rhs.displayTitle
    }
}
