import QuartzCore
import ReelsCreatorCore
import UIKit

enum OutroLogoOverlayRenderer {
    static func renderOverlayImage(
        logo: UIImage,
        canvasSize: CGSize = ReelRenderConfig.renderSize
    ) -> UIImage? {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              logo.size.width > 0,
              logo.size.height > 0 else {
            return nil
        }

        let scale = canvasSize.width / ReelRenderConfig.renderSize.width
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let paddedBounds = bounds.insetBy(dx: 140.0 * scale, dy: 240.0 * scale)
        guard paddedBounds.width > 0, paddedBounds.height > 0 else {
            return nil
        }

        let drawRect = ReelRenderConfig.aspectFitRect(for: logo.size, inside: paddedBounds)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            // Core Graphics shadows use unflipped (+Y up) coordinates; negate Y inside
            // UIGraphicsImageRenderer's flipped context to cast a downward drop shadow matching IntroTextOverlayRenderer.
            cgContext.setShadow(
                offset: CGSize(width: 0, height: -ReelRenderConfig.OverlayShadow.referenceOffsetY * scale),
                blur: ReelRenderConfig.OverlayShadow.referenceBlurRadius * scale,
                color: UIColor.black.withAlphaComponent(ReelRenderConfig.OverlayShadow.colorAlpha).cgColor
            )
            logo.draw(in: drawRect)
            cgContext.restoreGState()
        }
    }

    static func makeOverlayLayer(
        logo: UIImage,
        overlay: PlannedOutroLogoOverlay,
        renderSize: CGSize = ReelRenderConfig.renderSize
    ) -> CALayer? {
        guard overlay.durationSeconds > 0,
              let overlayImage = renderOverlayImage(logo: logo, canvasSize: renderSize),
              let cgImage = overlayImage.cgImage else {
            return nil
        }

        return OverlayCompositionBuilder.makeImageOverlayLayer(
            image: cgImage,
            renderSize: renderSize,
            startTimeSeconds: overlay.startTimeSeconds,
            durationSeconds: overlay.durationSeconds,
            fadeInDurationSeconds: overlay.fadeInDurationSeconds,
            fadeOutDurationSeconds: 0.0,
            animationKey: "outroLogoOpacity"
        )
    }
}
