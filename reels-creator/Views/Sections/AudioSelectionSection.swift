import PhotosUI
import SwiftUI

struct AudioSelectionSection: View {
    @Bindable var viewModel: ReelCreatorViewModel
    @Binding var audioVideoPickerItem: PhotosPickerItem?

    var body: some View {
        Section {
            Picker("Audio Source", selection: $viewModel.audioChoice) {
                ForEach(AudioSourceChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.audioChoice == .customTrack {
                if let customAudio = viewModel.customAudio {
                    HStack {
                        if let thumbnail = customAudio.thumbnail {
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
                            Text(customAudio.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(String(format: "Duration: %.1fs", customAudio.durationSeconds))
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

                let hasCustomAudio = viewModel.customAudio != nil

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
}
