import Foundation

public enum MediaClipKind: String, Codable, Equatable, Sendable {
    case photo
    case video
}

public struct MediaClipSpec: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: MediaClipKind
    public let sourceDurationSeconds: Double

    public init(id: UUID = UUID(), kind: MediaClipKind, sourceDurationSeconds: Double) {
        self.id = id
        self.kind = kind
        self.sourceDurationSeconds = sourceDurationSeconds
    }
}

public enum AudioSelectionMode: Equatable, Sendable {
    case none
    case customTrack(url: URL, durationSeconds: Double)

    public var isCustomTrack: Bool {
        switch self {
        case .none:
            return false
        case .customTrack:
            return true
        }
    }
}

public enum OutroSelectionMode: Equatable, Sendable {
    case none
    case staticLogo(backgroundColorHex: String, durationSeconds: Double = 2.0)
    case videoClip(durationSeconds: Double)
}

public struct ReelPolishSettings: Equatable, Sendable {
    public var defaultPhotoDuration: Double
    public var crossfadeEnabled: Bool
    public var crossfadeDuration: Double
    public var beatSyncEnabled: Bool

    public init(
        defaultPhotoDuration: Double = 2.5,
        crossfadeEnabled: Bool = true,
        crossfadeDuration: Double = 0.4,
        beatSyncEnabled: Bool = false
    ) {
        self.defaultPhotoDuration = defaultPhotoDuration
        self.crossfadeEnabled = crossfadeEnabled
        self.crossfadeDuration = crossfadeDuration
        self.beatSyncEnabled = beatSyncEnabled
    }
}
