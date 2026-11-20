import SwiftUI

struct IntroTextSection: View {
    @Bindable var viewModel: ReelCreatorViewModel
    var isIntroTextFocused: FocusState<Bool>.Binding

    var body: some View {
        Section {
            TextField("Optional opening text (e.g., New Arrivals)", text: $viewModel.introText, axis: .vertical)
                .lineLimit(2...5)
                .focused(isIntroTextFocused)

            if let spec = viewModel.resolvedIntroOverlaySpec {
                IntroTextPreviewCard(
                    text: spec.text,
                    backgroundThumbnail: viewModel.selectedItems.first?.thumbnail,
                    durationSeconds: viewModel.plannedIntroDurationSeconds
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
}
