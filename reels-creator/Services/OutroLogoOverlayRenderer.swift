import AVFoundation
import QuartzCore
import ReelsCreatorCore
import UIKit

enum OutroLogoOverlayRenderer {
    static let reelRenderSize = CGSize(width: 1080, height: 1920)
    static let previewCanvasSize = CGSize(width: 360, height: 640)

    static func renderOverlayImage(
        logo: UIImage,
        canvasSize: CGSize = reelRenderSize
    ) -> UIImage? {
        guard canvasSize.width > 0,
              canvasSize.height > 0,
              logo.size.width > 0,
              logo.size.height > 0 else {
            return nil
        }

        let scale = canvasSize.width / reelRenderSize.width
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let paddedBounds = bounds.insetBy(dx: 140.0 * scale, dy: 240.0 * scale)
        guard paddedBounds.width > 0, paddedBounds.height > 0 else {
            return nil
        }

        let drawRect = aspectFitRect(for: logo.size, inside: paddedBounds)

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
                offset: CGSize(width: 0, height: -4.0 * scale),
                blur: 18.0 * scale,
                color: UIColor.black.withAlphaComponent(0.72).cgColor
            )
            logo.draw(in: drawRect)
            cgContext.restoreGState()
        }
    }

    static func makeOverlayLayer(
        logo: UIImage,
        overlay: PlannedOutroLogoOverlay,
        renderSize: CGSize = reelRenderSize
    ) -> CALayer? {
        guard overlay.durationSeconds > 0,
              let overlayImage = renderOverlayImage(logo: logo, canvasSize: renderSize),
              let cgImage = overlayImage.cgImage else {
            return nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contents = cgImage
        overlayLayer.contentsScale = 1.0
        overlayLayer.contentsGravity = .resize
        overlayLayer.opacity = 0.0

        let animation = makeOpacityAnimation(for: overlay)
        overlayLayer.add(animation, forKey: "outroLogoOpacity")
        return overlayLayer
    }

    private static func makeOpacityAnimation(for overlay: PlannedOutroLogoOverlay) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + overlay.startTimeSeconds
        animation.duration = overlay.durationSeconds
        animation.isRemovedOnCompletion = false

        let duration = overlay.durationSeconds
        let fadeIn = max(0, min(overlay.fadeInDurationSeconds, duration))
        let fadeInEnd = fadeIn / duration

        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let linear = CAMediaTimingFunction(name: .linear)

        if fadeIn > 0 {
            // Safe to use .both because keyframe 0 is opacity 0.0 (hidden before beginTime)
            // and the final keyframe is 1.0 (held until the end of the Reel).
            animation.fillMode = .both
            if fadeInEnd < 0.9999 {
                animation.values = [0.0, 1.0, 1.0]
                animation.keyTimes = [0.0, NSNumber(value: fadeInEnd), 1.0]
                animation.timingFunctions = [easeOut, linear]
            } else {
                animation.values = [0.0, 1.0]
                animation.keyTimes = [0.0, 1.0]
                animation.timingFunctions = [easeOut]
            }
        } else {
            // Avoid .both when startTimeSeconds > 0 and opacity starts at 1.0,
            // which would reveal the logo before beginTime.
            animation.fillMode = overlay.startTimeSeconds > 0.0001 ? .forwards : .both
            animation.values = [1.0, 1.0]
            animation.keyTimes = [0.0, 1.0]
            animation.timingFunctions = [linear]
        }

        return animation
    }

    private static func aspectFitRect(for imageSize: CGSize, inside container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: container.midX - width / 2.0,
            y: container.midY - height / 2.0,
            width: width,
            height: height
        )
    }
}
