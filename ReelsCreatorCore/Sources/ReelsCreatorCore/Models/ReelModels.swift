import Foundation

public enum MediaClipKind: String, Codable, Equatable, Sendable {
    case photo
    case video
}

public struct MediaClipSpec: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: MediaClipKind
    public let sourceDurationSeconds: Double?

    public init(id: UUID = UUID(), kind: MediaClipKind, sourceDurationSeconds: Double? = nil) {
        self.id = id
        self.kind = kind
        self.sourceDurationSeconds = sourceDurationSeconds
    }

    public func resolvedSourceDuration(defaultPhotoDuration: Double) -> Double {
        let raw: Double
        switch kind {
        case .photo:
            raw = sourceDurationSeconds ?? defaultPhotoDuration
        case .video:
            raw = sourceDurationSeconds ?? 0.1
        }
        return max(0.1, raw)
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
    public static let defaultLogoOverlayDurationSeconds: Double = 2.0
    public static let defaultLogoOverlayFadeInDurationSeconds: Double = 0.3

    case none
    case logoOverlay(
        durationSeconds: Double = defaultLogoOverlayDurationSeconds,
        fadeInDurationSeconds: Double = defaultLogoOverlayFadeInDurationSeconds
    )
    case videoClip(durationSeconds: Double)
}

public struct ReelPolishSettings: Equatable, Sendable {
    public var defaultPhotoDuration: Double
    public var crossfadeEnabled: Bool
    public var crossfadeDuration: Double
    public var beatSyncEnabled: Bool

    public init(
        defaultPhotoDuration: Double = 1.5,
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

public struct IntroTextOverlaySpec: Equatable, Sendable {
    public static let defaultDurationSeconds: Double = 3.0
    public static let defaultFadeInDurationSeconds: Double = 0.3
    public static let defaultFadeOutDurationSeconds: Double = 0.4

    public let text: String
    public let durationSeconds: Double
    public let fadeInDurationSeconds: Double
    public let fadeOutDurationSeconds: Double

    public init?(
        rawText: String,
        durationSeconds: Double = defaultDurationSeconds,
        fadeInDurationSeconds: Double = defaultFadeInDurationSeconds,
        fadeOutDurationSeconds: Double = defaultFadeOutDurationSeconds
    ) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, durationSeconds > 0 else {
            return nil
        }

        self.text = trimmed
        self.durationSeconds = durationSeconds
        self.fadeInDurationSeconds = max(0, fadeInDurationSeconds)
        self.fadeOutDurationSeconds = max(0, fadeOutDurationSeconds)
    }
}
