import AVKit
import SwiftUI

struct ExportResultSheet: View {
    let videoURL: URL
    let isSaving: Bool
    let savedSuccess: Bool
    let onSaveToPhotos: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.1))
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                }

                VStack(spacing: 12) {
                    Button {
                        onSaveToPhotos()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: savedSuccess ? "checkmark.circle.fill" : "square.and.arrow.down")
                            }
                            Text(savedSuccess ? "Saved to iPhone Photos" : "Save to iPhone Photos")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(savedSuccess ? .green : .accentColor)
                    .disabled(isSaving || savedSuccess)

                    ShareLink(item: videoURL) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share to Instagram or Files")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Reel Ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                let newPlayer = AVPlayer(url: videoURL)
                player = newPlayer
                newPlayer.play()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }
}
