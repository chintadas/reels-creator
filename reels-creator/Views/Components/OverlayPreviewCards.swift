import SwiftUI

struct ReelOverlayPreviewCard: View {
    let overlayImage: UIImage?
    let backgroundThumbnail: UIImage?
    let caption: String

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

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct IntroTextPreviewCard: View {
    let text: String
    let backgroundThumbnail: UIImage?
    let durationSeconds: Double

    @State private var overlayImage: UIImage?

    private var captionText: String {
        if durationSeconds > 0.01 {
            return String(format: "Preview • Fades in & out over first %.1fs", durationSeconds)
        } else {
            return "Preview • Omitted (no time before outro)"
        }
    }

    var body: some View {
        ReelOverlayPreviewCard(
            overlayImage: overlayImage,
            backgroundThumbnail: backgroundThumbnail,
            caption: captionText
        )
        .task(id: text) {
            let currentText = text
            if overlayImage != nil {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            let rendered = await Task.detached(priority: .userInitiated) {
                IntroTextOverlayRenderer.renderOverlayImage(
                    text: currentText,
                    canvasSize: ReelRenderConfig.previewCanvasSize
                )
            }.value
            if !Task.isCancelled {
                overlayImage = rendered
            }
        }
    }
}

struct OutroLogoPreviewCard: View {
    let logoImage: UIImage
    let backgroundThumbnail: UIImage?
    let durationSeconds: Double

    @State private var overlayImage: UIImage?

    var body: some View {
        ReelOverlayPreviewCard(
            overlayImage: overlayImage,
            backgroundThumbnail: backgroundThumbnail,
            caption: String(format: "Preview • Fades in over last %.1fs", durationSeconds)
        )
        .task(id: ObjectIdentifier(logoImage)) {
            let logo = logoImage
            let rendered = await Task.detached(priority: .userInitiated) {
                OutroLogoOverlayRenderer.renderOverlayImage(
                    logo: logo,
                    canvasSize: ReelRenderConfig.previewCanvasSize
                )
            }.value
            if !Task.isCancelled {
                overlayImage = rendered
            }
        }
    }
}
