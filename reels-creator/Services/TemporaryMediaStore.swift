import Foundation

enum TemporaryMediaStore {
    private static var temporaryDirectoryPathPrefix: String {
        let path = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return path.hasSuffix("/") ? path : path + "/"
    }

    static func makeTemporaryURL(prefix: String, fileExtension: String?) -> URL {
        var url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        if let fileExtension, !fileExtension.isEmpty {
            url = url.appendingPathExtension(fileExtension)
        }
        return url
    }

    static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    static func copySecurityScopedFile(from url: URL, prefix: String) throws -> URL {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        let destination = makeTemporaryURL(prefix: prefix, fileExtension: ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    static func copyFile(from sourceURL: URL, prefix: String, defaultExtension: String) throws -> URL {
        let ext = sourceURL.pathExtension.isEmpty ? defaultExtension : sourceURL.pathExtension
        let destination = makeTemporaryURL(prefix: prefix, fileExtension: ext)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func writeData(_ data: Data, prefix: String, fileExtension: String) throws -> URL {
        let destination = makeTemporaryURL(prefix: prefix, fileExtension: fileExtension)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func removeIfTemporary(_ url: URL?) {
        guard let url else { return }
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(temporaryDirectoryPathPrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func removeItemIfPresent(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
