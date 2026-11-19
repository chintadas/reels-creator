import Foundation
import Photos

enum PhotoLibrarySaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case saveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photo Library access was denied. Enable Photos access in iOS Settings to save Reels."
            case .saveFailed(let error):
                return "Could not save Reel to Photos: \(error.localizedDescription)"
            }
        }
    }

    static func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } catch {
            throw SaveError.saveFailed(error)
        }
    }
}
