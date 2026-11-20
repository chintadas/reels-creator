import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ReelCreatorView: View {
    @State private var viewModel = ReelCreatorViewModel()

    @State private var mediaPickerItems: [PhotosPickerItem] = []
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var outroVideoPickerItem: PhotosPickerItem?
    @State private var audioVideoPickerItem: PhotosPickerItem?

    @State private var showLogoFileImporter = false
    @State private var showOutroVideoImporter = false

    @FocusState private var isIntroTextFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                MediaSelectionSection(
                    viewModel: viewModel,
                    mediaPickerItems: $mediaPickerItems
                )
                AudioSelectionSection(
                    viewModel: viewModel,
                    audioVideoPickerItem: $audioVideoPickerItem
                )
                PolishSection(viewModel: viewModel)
                IntroTextSection(
                    viewModel: viewModel,
                    isIntroTextFocused: $isIntroTextFocused
                )
                OutroSection(
                    viewModel: viewModel,
                    logoPickerItem: $logoPickerItem,
                    outroVideoPickerItem: $outroVideoPickerItem,
                    showLogoFileImporter: $showLogoFileImporter,
                    showOutroVideoImporter: $showOutroVideoImporter
                )
                GenerateSection(viewModel: viewModel)
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
                isPresented: $showLogoFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleImporterResult(result) { url in
                    Task { await viewModel.importLogoFile(url: url) }
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
                if let exportResult = viewModel.exportResult {
                    ExportResultSheet(
                        videoURL: exportResult.videoURL,
                        isSaving: exportResult.saveState == .saving,
                        savedSuccess: exportResult.saveState == .saved,
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
