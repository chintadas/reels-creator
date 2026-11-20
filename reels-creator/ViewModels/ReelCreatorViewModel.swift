import Foundation
import Observation
import PhotosUI
import ReelsCreatorCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class ReelCreatorViewModel {
    static let defaultLogoAssetName = "DefaultOutroLogo"
    static let defaultOutroDurationSeconds: Double = OutroSelectionMode.defaultLogoOverlayDurationSeconds

    static func loadDefaultLogoImage() -> UIImage? {
        UIImage(named: defaultLogoAssetName)
    }

    private let dependencies: ReelCreatorDependencies
    private var nextClipSequenceNumber = 1

    var selectedItems: [SelectedMediaItem] = []
    var isLoadingMedia = false

    var audioChoice: AudioSourceChoice = .instagramAudio
    var customAudio: CustomAudioTrack?
    var isExtractingAudio = false

    var outroType: OutroTypeChoice = .logoOverlay
    var logoImage: UIImage? = ReelCreatorViewModel.loadDefaultLogoImage()
    var isUsingDefaultLogo: Bool = true
    var outroDurationSeconds: Double = ReelCreatorViewModel.defaultOutroDurationSeconds
    var outroVideo: OutroVideoClip?

    var polishSettings = ReelPolishSettings()
    var introText: String = ""

    var isExporting = false
    var exportProgressMessage = ""
    var exportResult: ExportResultState?
    var showExportSheet = false
    var errorMessage: String?

    init(dependencies: ReelCreatorDependencies = .live) {
        self.dependencies = dependencies
    }

    var resolvedIntroOverlaySpec: IntroTextOverlaySpec? {
        IntroTextOverlaySpec(rawText: introText)
    }

    var isOutroLogoCustomized: Bool {
        !isUsingDefaultLogo || abs(outroDurationSeconds - Self.defaultOutroDurationSeconds) > 0.001
    }

    var canGenerateReel: Bool {
        validationHint == nil && !isExporting
    }

    var validationHint: String? {
        if selectedItems.isEmpty {
            return "Select at least one photo or video to create a Reel."
        }
        if isLoadingMedia {
            return "Loading selected media..."
        }
        if isExtractingAudio {
            return "Extracting audio from selected video..."
        }
        if audioChoice == .customTrack && customAudio == nil {
            return "Extract audio from a video or switch back to No Music (Add in IG)."
        }
        if outroType == .logoOverlay && logoImage == nil {
            return "Pick your store logo image (PNG) or set Outro to None."
        }
        if outroType == .videoClip && outroVideo == nil {
            return "Pick a pre-made outro video clip or set Outro to None."
        }
        return nil
    }

    var plannedTimeline: PlannedTimeline {
        let specs = selectedItems.map { item in
            MediaClipSpec(
                id: item.id,
                kind: item.kind,
                sourceDurationSeconds: item.kind == .photo ? nil : item.durationSeconds
            )
        }
        return TimelinePlanner.plan(
            clips: specs,
            audio: resolvedAudioMode(),
            outro: resolvedOutroMode(),
            settings: polishSettings,
            introOverlay: resolvedIntroOverlaySpec
        )
    }

    var estimatedDurationSeconds: Double {
        plannedTimeline.totalDurationSeconds
    }

    var plannedIntroDurationSeconds: Double {
        if selectedItems.isEmpty {
            return IntroTextOverlaySpec.defaultDurationSeconds
        }
        return plannedTimeline.introOverlay?.durationSeconds ?? 0.0
    }

    func loadSelectedPickerItems(_ pickerItems: [PhotosPickerItem]) async {
        guard !pickerItems.isEmpty else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false }

        for pickerItem in pickerItems {
            do {
                let sequence = nextClipSequenceNumber
                if let item = try await dependencies.loadMediaItem(
                    pickerItem,
                    polishSettings.defaultPhotoDuration,
                    sequence
                ) {
                    selectedItems.append(item)
                    nextClipSequenceNumber += 1
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
        for item in selectedItems where item.id == id {
            dependencies.removeTemporaryFile(item.mediaURL)
        }
        selectedItems.removeAll { $0.id == id }
    }

    func clearAllItems() {
        for item in selectedItems {
            dependencies.removeTemporaryFile(item.mediaURL)
        }
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
            let track = try await dependencies.extractCustomAudio(item)
            let previousAudioURL = customAudio?.url
            customAudio = track
            audioChoice = .customTrack
            if previousAudioURL != track.url {
                dependencies.removeTemporaryFile(previousAudioURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCustomAudio() {
        dependencies.removeTemporaryFile(customAudio?.url)
        customAudio = nil
        audioChoice = .instagramAudio
        polishSettings.beatSyncEnabled = false
    }

    func loadLogoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let image = try await dependencies.loadLogoImage(item) {
                logoImage = image
                isUsingDefaultLogo = false
                outroType = .logoOverlay
            }
        } catch {
            errorMessage = "Could not load logo image: \(error.localizedDescription)"
        }
    }

    func importLogoFile(url: URL) async {
        do {
            let image = try await dependencies.importLogoImage(url)
            logoImage = image
            isUsingDefaultLogo = false
            outroType = .logoOverlay
        } catch {
            errorMessage = "Could not import logo file: \(error.localizedDescription)"
        }
    }

    func resetOutroToDefault() {
        logoImage = Self.loadDefaultLogoImage()
        isUsingDefaultLogo = true
        outroDurationSeconds = Self.defaultOutroDurationSeconds
        outroType = .logoOverlay
    }

    func importOutroVideo(url: URL) async {
        do {
            let clip = try await dependencies.importOutroVideo(url)
            let previousURL = outroVideo?.url
            outroVideo = clip
            outroType = .videoClip
            if previousURL != clip.url {
                dependencies.removeTemporaryFile(previousURL)
            }
        } catch {
            errorMessage = "Could not import outro video: \(error.localizedDescription)"
        }
    }

    func loadOutroVideoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let clip = try await dependencies.loadOutroVideo(item) {
                let previousURL = outroVideo?.url
                outroVideo = clip
                outroType = .videoClip
                if previousURL != clip.url {
                    dependencies.removeTemporaryFile(previousURL)
                }
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

        defer {
            isExporting = false
            exportProgressMessage = ""
        }

        let request = ReelCompositionRequest(
            items: selectedItems,
            audioMode: resolvedAudioMode(),
            outroMode: resolvedOutroMode(),
            outroLogoImage: logoImage,
            outroVideoURL: outroVideo?.url,
            polishSettings: polishSettings,
            introOverlay: resolvedIntroOverlaySpec
        )

        do {
            let outputURL = try await dependencies.composeReel(request) { [weak self] status in
                self?.exportProgressMessage = status
            }
            let previousExportURL = exportResult?.videoURL
            exportResult = ExportResultState(videoURL: outputURL)
            showExportSheet = true
            if previousExportURL != outputURL {
                dependencies.removeTemporaryFile(previousExportURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveExportedReelToPhotos() async {
        guard let currentResult = exportResult, currentResult.saveState == .idle else { return }
        exportResult?.saveState = .saving

        do {
            try await dependencies.saveVideoToPhotos(currentResult.videoURL)
            exportResult?.saveState = .saved
        } catch {
            exportResult?.saveState = .idle
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedAudioMode() -> AudioSelectionMode {
        switch audioChoice {
        case .instagramAudio:
            return .none
        case .customTrack:
            if let customAudio {
                return .customTrack(url: customAudio.url, durationSeconds: customAudio.durationSeconds)
            }
            return .none
        }
    }

    private func resolvedOutroMode() -> OutroSelectionMode {
        switch outroType {
        case .none:
            return .none
        case .logoOverlay:
            return .logoOverlay(durationSeconds: outroDurationSeconds)
        case .videoClip:
            return .videoClip(durationSeconds: max(0.2, outroVideo?.durationSeconds ?? 0.2))
        }
    }
}
