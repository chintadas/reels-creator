import PhotosUI
import ReelsCreatorCore
import SwiftUI

struct MediaSelectionSection: View {
    @Bindable var viewModel: ReelCreatorViewModel
    @Binding var mediaPickerItems: [PhotosPickerItem]

    var body: some View {
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
                            MediaClipCard(
                                item: item,
                                canMoveLeft: index > 0,
                                canMoveRight: index < viewModel.selectedItems.count - 1,
                                onRemove: { viewModel.removeItem(id: item.id) },
                                onMoveLeft: { viewModel.moveItemLeft(id: item.id) },
                                onMoveRight: { viewModel.moveItemRight(id: item.id) }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }

                LabeledDurationSlider(
                    title: "Photo Duration",
                    value: $viewModel.polishSettings.defaultPhotoDuration,
                    range: 1.0...5.0,
                    step: 0.5
                )

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
}

private struct MediaClipCard: View {
    let item: SelectedMediaItem
    let canMoveLeft: Bool
    let canMoveRight: Bool
    let onRemove: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void

    var body: some View {
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

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            HStack(spacing: 14) {
                Button(action: onMoveLeft) {
                    Image(systemName: "chevron.left.circle")
                }
                .disabled(!canMoveLeft)

                Button(action: onMoveRight) {
                    Image(systemName: "chevron.right.circle")
                }
                .disabled(!canMoveRight)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}
