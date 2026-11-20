import SwiftUI

struct GenerateSection: View {
    let viewModel: ReelCreatorViewModel

    var body: some View {
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
}
