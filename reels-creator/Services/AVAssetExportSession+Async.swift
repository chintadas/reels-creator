import AVFoundation
import Foundation

extension AVAssetExportSession {
    func exportCompat(to outputURL: URL, as fileType: AVFileType) async throws {
        if #available(iOS 18.0, *) {
            try await export(to: outputURL, as: fileType)
        } else {
            self.outputURL = outputURL
            self.outputFileType = fileType
            await export()
            if status != .completed {
                throw error ?? NSError(
                    domain: AVFoundationErrorDomain,
                    code: AVError.unknown.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "Export failed with status \(status.rawValue)."]
                )
            }
        }
    }
}
