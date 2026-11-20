import SwiftUI

struct PolishSection: View {
    @Bindable var viewModel: ReelCreatorViewModel

    var body: some View {
        Section {
            Toggle("Crossfade Transitions", isOn: $viewModel.polishSettings.crossfadeEnabled)

            if viewModel.polishSettings.crossfadeEnabled {
                LabeledDurationSlider(
                    title: "Crossfade Duration",
                    value: $viewModel.polishSettings.crossfadeDuration,
                    range: 0.2...0.8,
                    step: 0.1,
                    format: "%.2fs"
                )
            }

            Toggle("Beat-Sync Photos to Audio", isOn: $viewModel.polishSettings.beatSyncEnabled)
                .disabled(
                    viewModel.audioChoice != .customTrack
                        || viewModel.customAudio == nil
                        || viewModel.isExtractingAudio
                )
        } header: {
            Text("3. Polish & Transitions")
        } footer: {
            Text("Beat-Sync adjusts photo durations to land cuts on detected audio beats. Ken Burns pan/zoom is disabled.")
        }
    }
}
