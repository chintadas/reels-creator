import PhotosUI
import SwiftUI

struct OutroSection: View {
    @Bindable var viewModel: ReelCreatorViewModel
    @Binding var logoPickerItem: PhotosPickerItem?
    @Binding var outroVideoPickerItem: PhotosPickerItem?
    @Binding var showLogoFileImporter: Bool
    @Binding var showOutroVideoImporter: Bool

    var body: some View {
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

            case .logoOverlay:
                let hasLogo = viewModel.logoImage != nil

                if let logo = viewModel.logoImage {
                    OutroLogoPreviewCard(
                        logoImage: logo,
                        backgroundThumbnail: viewModel.selectedItems.last?.thumbnail,
                        durationSeconds: viewModel.outroDurationSeconds
                    )
                }

                Label {
                    Text(viewModel.isUsingDefaultLogo ? "Default (@snazzysboutique)" : "Custom Logo")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: viewModel.isUsingDefaultLogo ? "checkmark.seal.fill" : "photo")
                        .foregroundStyle(viewModel.isUsingDefaultLogo ? Color.accentColor : Color.secondary)
                }
                .font(.subheadline)

                PhotosPicker(selection: $logoPickerItem, matching: .images) {
                    Label(
                        hasLogo ? "Replace Logo from Photos" : "Pick Logo from Photos",
                        systemImage: "photo"
                    )
                }

                Button {
                    showLogoFileImporter = true
                } label: {
                    Label(
                        hasLogo ? "Replace PNG from Files" : "Pick PNG from Files",
                        systemImage: "folder"
                    )
                }

                LabeledDurationSlider(
                    title: "Outro Duration",
                    value: $viewModel.outroDurationSeconds,
                    range: 1.0...4.0,
                    step: 0.5
                )

                if viewModel.isOutroLogoCustomized {
                    Button("Reset to Default") {
                        viewModel.resetOutroToDefault()
                    }
                    .font(.subheadline)
                }

            case .videoClip:
                if let outroVideo = viewModel.outroVideo {
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(outroVideo.name)
                                .font(.subheadline.weight(.medium))
                            Text(String(format: "Duration: %.1fs", outroVideo.durationSeconds))
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
        } footer: {
            switch viewModel.outroType {
            case .none:
                Text("No outro overlay or clip will be added.")
            case .logoOverlay:
                Text("Defaults to @snazzysboutique for 2.0s. Fades in transparently over the end of the Reel without adding extra length.")
            case .videoClip:
                Text("Appends a pre-made outro video clip to the end of the Reel.")
            }
        }
    }
}
