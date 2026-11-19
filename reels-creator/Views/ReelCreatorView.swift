import PhotosUI
import ReelsCreatorCore
import SwiftUI
import UniformTypeIdentifiers

struct ReelCreatorView: View {
    @State private var viewModel = ReelCreatorViewModel()

    @State private var mediaPickerItems: [PhotosPickerItem] = []
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var outroVideoPickerItem: PhotosPickerItem?
    @State private var audioVideoPickerItem: PhotosPickerItem?

    @State private var showAudioImporter = false
    @State private var showLogoFileImporter = false
    @State private var showOutroVideoImporter = false

    @FocusState private var isIntroTextFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                mediaSection
                audioSection
                polishSection
                introTextSection
                outroSection
                generateSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Reels Creator")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isIntroTextFocused = false
                    }
                }
            }
            .overlay {
                if viewModel.isExporting {
                    exportingOverlay
                }
            }
            .onChange(of: mediaPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task {
                    await viewModel.loadSelectedPickerItems(newItems)
                    mediaPickerItems = []
                }
            }
            .onChange(of: logoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await viewModel.loadLogoItem(newItem)
                    logoPickerItem = nil
                }
            }
            .onChange(of: outroVideoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await viewModel.loadOutroVideoItem(newItem)
                    outroVideoPickerItem = nil
                }
            }
            .onChange(of: audioVideoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await viewModel.extractAudioFromVideoItem(newItem)
                    audioVideoPickerItem = nil
                }
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleImporterResult(result) { url in
                    Task { await viewModel.importAudioFile(url: url) }
                }
            }
            .fileImporter(
                isPresented: $showLogoFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleImporterResult(result) { url in
                    viewModel.importLogoFile(url: url)
                }
            }
            .fileImporter(
                isPresented: $showOutroVideoImporter,
                allowedContentTypes: [.movie],
                allowsMultipleSelection: false
            ) { result in
                handleImporterResult(result) { url in
                    Task { await viewModel.importOutroVideo(url: url) }
                }
            }
            .sheet(isPresented: $viewModel.showExportSheet) {
                if let url = viewModel.exportedVideoURL {
                    ExportResultSheet(
                        videoURL: url,
                        isSaving: viewModel.isSavingToPhotos,
                        savedSuccess: viewModel.savedToPhotosSuccess,
                        onSaveToPhotos: {
                            Task { await viewModel.saveExportedReelToPhotos() }
                        }
                    )
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var mediaSection: some View {
        Section {
            PhotosPicker(
                selection: $mediaPickerItems,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Label("Add Photos & Videos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
            }

            if viewModel.isLoadingMedia {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading selected media...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.selectedItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.selectedItems.enumerated()), id: \.element.id) { index, item in
                            mediaClipCard(item: item, index: index)
                        }
                    }
                    .padding(.vertical, 6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Photo Duration")
                        Spacer()
                        Text(String(format: "%.1fs", viewModel.polishSettings.defaultPhotoDuration))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $viewModel.polishSettings.defaultPhotoDuration,
                        in: 1.0...5.0,
                        step: 0.5
                    )
                }

                Button("Clear All Clips", role: .destructive) {
                    viewModel.clearAllItems()
                }
                .font(.subheadline)
            }
        } header: {
            Text("1. Photos & Videos")
        } footer: {
            Text("Clips are formatted to 1080×1920 (9:16) using a static center crop.")
        }
    }

    private func mediaClipCard(item: SelectedMediaItem, index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        Text(item.kind == .video ? String(format: "%.1fs", item.durationSeconds) : "IMG")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.65), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(5)
                    }

                Button {
                    viewModel.removeItem(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            HStack(spacing: 14) {
                Button {
                    viewModel.moveItemLeft(id: item.id)
                } label: {
                    Image(systemName: "chevron.left.circle")
                }
                .disabled(index == 0)

                Button {
                    viewModel.moveItemRight(id: item.id)
                } label: {
                    Image(systemName: "chevron.right.circle")
                }
                .disabled(index == viewModel.selectedItems.count - 1)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var audioSection: some View {
        Section {
            Picker("Audio Source", selection: $viewModel.audioChoice) {
                ForEach(AudioSourceChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.audioChoice == .customTrack {
                if let audioName = viewModel.customAudioName {
                    HStack {
                        if let thumbnail = viewModel.customAudioThumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(3)
                                        .background(.black.opacity(0.65), in: Circle())
                                        .padding(2)
                                }
                        } else {
                            Image(systemName: "music.note")
                                .foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading) {
                            Text(audioName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(String(format: "Duration: %.1fs", viewModel.customAudioDurationSeconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            viewModel.clearCustomAudio()
                        }
                        .font(.caption)
                        .disabled(viewModel.isExtractingAudio)
                    }
                }

                if viewModel.isExtractingAudio {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Extracting audio from video...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                let hasCustomAudio = viewModel.customAudioName != nil

                Button {
                    showAudioImporter = true
                } label: {
                    Label(
                        hasCustomAudio ? "Replace with Audio File" : "Choose Audio File (MP3 / M4A)",
                        systemImage: "folder"
                    )
                }
                .disabled(viewModel.isExtractingAudio)

                PhotosPicker(
                    selection: $audioVideoPickerItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label(
                        hasCustomAudio ? "Replace with Video Audio" : "Extract Audio from Video",
                        systemImage: "video"
                    )
                }
                .disabled(viewModel.isExtractingAudio)
            }
        } header: {
            Text("2. Audio")
        } footer: {
            if viewModel.audioChoice == .customTrack {
                Text("Original audio on selected video clips is automatically muted when custom background audio is active.")
            } else {
                Text("Exports with original clip sound (or silent for photos) so you can attach trending music inside Instagram.")
            }
        }
    }

    private var polishSection: some View {
        Section {
            Toggle("Crossfade Transitions", isOn: $viewModel.polishSettings.crossfadeEnabled)

            if viewModel.polishSettings.crossfadeEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Crossfade Duration")
                        Spacer()
                        Text(String(format: "%.2fs", viewModel.polishSettings.crossfadeDuration))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $viewModel.polishSettings.crossfadeDuration,
                        in: 0.2...0.8,
                        step: 0.1
                    )
                }
            }

            Toggle("Beat-Sync Photos to Audio", isOn: $viewModel.polishSettings.beatSyncEnabled)
                .disabled(viewModel.audioChoice != .customTrack || viewModel.customAudioURL == nil || viewModel.isExtractingAudio)
        } header: {
            Text("3. Polish & Transitions")
        } footer: {
            Text("Beat-Sync adjusts photo durations to land cuts on detected audio beats. Ken Burns pan/zoom is disabled.")
        }
    }

    private var introTextSection: some View {
        Section {
            TextField("Optional opening text (e.g., New Arrivals)", text: $viewModel.introText, axis: .vertical)
                .lineLimit(2...5)
                .focused($isIntroTextFocused)

            if let spec = viewModel.resolvedIntroOverlaySpec {
                IntroTextPreviewCard(
                    text: spec.text,
                    backgroundThumbnail: viewModel.selectedItems.first?.thumbnail
                )

                Button("Clear Intro Text", role: .destructive) {
                    viewModel.clearIntroText()
                }
                .font(.subheadline)
            }
        } header: {
            Text("4. Intro Text")
        } footer: {
            Text("Optional. White centered text fades in and out over the first 3 seconds (stops before any outro). Leave blank to omit.")
        }
    }

    private var outroSection: some View {
        Section {
            Picker("Outro Type", selection: $viewModel.outroType) {
                ForEach(OutroTypeChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            switch viewModel.outroType {
            case .none:
                EmptyView()

            case .staticLogo:
                HStack(spacing: 14) {
                    if let logo = viewModel.logoImage {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .padding(6)
                            .background(viewModel.outroBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $logoPickerItem, matching: .images) {
                            Label("Pick Logo from Photos", systemImage: "photo")
                        }
                        Button {
                            showLogoFileImporter = true
                        } label: {
                            Label("Pick PNG from Files", systemImage: "folder")
                        }
                    }
                    .font(.subheadline)
                }

                ColorPicker("Background Color", selection: $viewModel.outroBackgroundColor, supportsOpacity: false)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Outro Duration")
                        Spacer()
                        Text(String(format: "%.1fs", viewModel.outroDurationSeconds))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.outroDurationSeconds, in: 1.0...4.0, step: 0.5)
                }

            case .videoClip:
                if let name = viewModel.outroVideoName {
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                            Text(String(format: "Duration: %.1fs", viewModel.outroVideoDurationSeconds))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                PhotosPicker(selection: $outroVideoPickerItem, matching: .videos) {
                    Label("Pick Outro Video from Photos", systemImage: "video")
                }

                Button {
                    showOutroVideoImporter = true
                } label: {
                    Label("Pick Outro Video from Files", systemImage: "folder")
                }
            }
        } header: {
            Text("5. Store Logo Outro")
        }
    }

    private var generateSection: some View {
        Section {
            if !viewModel.selectedItems.isEmpty {
                HStack {
                    Text("Estimated Reel Length")
                    Spacer()
                    Text(String(format: "%.1fs", viewModel.estimatedDurationSeconds))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Button {
                Task { await viewModel.generateReel() }
            } label: {
                HStack {
                    Spacer()
                    Label("Generate Reel", systemImage: "wand.and.stars")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .disabled(!viewModel.canGenerateReel)

            if let hint = viewModel.validationHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var exportingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Creating Reel")
                    .font(.headline)
                Text(viewModel.exportProgressMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func handleImporterResult(
        _ result: Result<[URL], Error>,
        onSuccess: (URL) -> Void
    ) {
        switch result {
        case .success(let urls):
            if let first = urls.first {
                onSuccess(first)
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

private struct IntroTextPreviewCard: View {
    let text: String
    let backgroundThumbnail: UIImage?

    @State private var overlayImage: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let backgroundThumbnail {
                    Image(uiImage: backgroundThumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 144, height: 256)
                        .clipped()
                } else {
                    Color.black.opacity(0.9)
                }

                if let overlayImage {
                    Image(uiImage: overlayImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 144, height: 256)
                }
            }
            .frame(width: 144, height: 256)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            Text("Preview • Fades in & out over first 3.0s")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onAppear {
            refreshOverlay()
        }
        .onChange(of: text) { _, _ in
            refreshOverlay()
        }
    }

    private func refreshOverlay() {
        overlayImage = IntroTextOverlayRenderer.renderOverlayImage(
            text: text,
            canvasSize: IntroTextOverlayRenderer.previewCanvasSize
        )
    }
}
