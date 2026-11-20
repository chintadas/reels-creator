import AVFoundation
import QuartzCore
import ReelsCreatorCore
import UIKit

enum IntroTextOverlayRenderer {
    static let reelRenderSize = CGSize(width: 1080, height: 1920)
    static let previewCanvasSize = CGSize(width: 360, height: 640)

    private struct TextLayoutSpec {
        let attributes: [NSAttributedString.Key: Any]
        let boundingHeight: CGFloat
    }

    static func renderOverlayImage(
        text: String,
        canvasSize: CGSize = reelRenderSize
    ) -> UIImage? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let scale = canvasSize.width / reelRenderSize.width
        let maxTextWidth = canvasSize.width - (240.0 * scale)
        let maxTextHeight = 960.0 * scale
        guard maxTextWidth > 0, maxTextHeight > 0 else {
            return nil
        }

        let layout = resolveTextLayout(
            for: trimmedText,
            scale: scale,
            maxTextWidth: maxTextWidth,
            maxTextHeight: maxTextHeight
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            let drawHeight = min(ceil(layout.boundingHeight), maxTextHeight)
            let drawRect = CGRect(
                x: (canvasSize.width - maxTextWidth) / 2.0,
                y: (canvasSize.height - drawHeight) / 2.0,
                width: maxTextWidth,
                height: drawHeight
            )
            (trimmedText as NSString).draw(
                with: drawRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
                attributes: layout.attributes,
                context: nil
            )
        }
    }

    static func makeOverlayLayer(
        for overlay: PlannedIntroOverlay,
        renderSize: CGSize = reelRenderSize
    ) -> CALayer? {
        guard overlay.durationSeconds > 0,
              let overlayImage = renderOverlayImage(text: overlay.text, canvasSize: renderSize),
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
        overlayLayer.add(animation, forKey: "introTextOpacity")
        return overlayLayer
    }

    static func makeAnimationTool(
        for overlay: PlannedIntroOverlay,
        renderSize: CGSize = reelRenderSize
    ) -> AVVideoCompositionCoreAnimationTool? {
        guard let overlayLayer = makeOverlayLayer(for: overlay, renderSize: renderSize) else {
            return nil
        }
        return makeAnimationTool(overlayLayers: [overlayLayer], renderSize: renderSize)
    }

    static func makeAnimationTool(
        overlayLayers: [CALayer],
        renderSize: CGSize = reelRenderSize
    ) -> AVVideoCompositionCoreAnimationTool? {
        guard !overlayLayers.isEmpty else {
            return nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = CGRect(origin: .zero, size: renderSize)

        let parentLayer = CALayer()
        parentLayer.frame = bounds

        let videoLayer = CALayer()
        videoLayer.frame = bounds

        parentLayer.addSublayer(videoLayer)
        for overlayLayer in overlayLayers {
            parentLayer.addSublayer(overlayLayer)
        }

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func resolveTextLayout(
        for text: String,
        scale: CGFloat,
        maxTextWidth: CGFloat,
        maxTextHeight: CGFloat
    ) -> TextLayoutSpec {
        let explicitLineCount = text.components(separatedBy: .newlines).count
        let targetMaxLines = max(4, explicitLineCount)
        let wordTokens = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var candidates = Array(stride(from: 84.0 as CGFloat, through: 42.0 as CGFloat, by: -4.0))
        if candidates.last != 42.0 {
            candidates.append(42.0)
        }

        var fallbackLayout: TextLayoutSpec?

        for refSize in candidates {
            let font = UIFont.systemFont(ofSize: refSize * scale, weight: .bold)
            let attributes = textAttributes(font: font, refSize: refSize, scale: scale)
            let boundingRect = (text as NSString).boundingRect(
                with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )

            let longestWordFits = wordTokens.allSatisfy { token in
                (token as NSString).size(withAttributes: [.font: font]).width <= maxTextWidth
            }

            let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
            let lineStride = max(1.0, font.lineHeight + (paragraphStyle?.lineSpacing ?? 0))
            let estimatedLines = Int(ceil(boundingRect.height / lineStride))

            let candidateLayout = TextLayoutSpec(
                attributes: attributes,
                boundingHeight: boundingRect.height
            )

            if boundingRect.height <= maxTextHeight && longestWordFits {
                if estimatedLines <= targetMaxLines {
                    return candidateLayout
                }
                if fallbackLayout == nil {
                    fallbackLayout = candidateLayout
                }
            }
        }

        if let fallbackLayout {
            return fallbackLayout
        }

        let minRefSize: CGFloat = 42.0
        let minFont = UIFont.systemFont(ofSize: minRefSize * scale, weight: .bold)
        let minAttributes = textAttributes(font: minFont, refSize: minRefSize, scale: scale)
        let minRect = (text as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: minAttributes,
            context: nil
        )
        return TextLayoutSpec(attributes: minAttributes, boundingHeight: minRect.height)
    }

    private static func textAttributes(
        font: UIFont,
        refSize: CGFloat,
        scale: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = refSize * 0.14 * scale

        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.72)
        shadow.shadowOffset = CGSize(width: 0, height: 4.0 * scale)
        shadow.shadowBlurRadius = 18.0 * scale

        return [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
    }

    private static func makeOpacityAnimation(for overlay: PlannedIntroOverlay) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + overlay.startTimeSeconds
        animation.duration = overlay.durationSeconds
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both

        let duration = overlay.durationSeconds
        let fadeIn = max(0, min(overlay.fadeInDurationSeconds, duration))
        let fadeOut = max(0, min(overlay.fadeOutDurationSeconds, duration))
        let fadeInEnd = fadeIn / duration
        let fadeOutStart = (duration - fadeOut) / duration

        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let linear = CAMediaTimingFunction(name: .linear)
        let easeIn = CAMediaTimingFunction(name: .easeIn)

        if fadeIn > 0 && fadeOut > 0 {
            if fadeOutStart > fadeInEnd + 0.0001 {
                animation.values = [0.0, 1.0, 1.0, 0.0]
                animation.keyTimes = [0.0, NSNumber(value: fadeInEnd), NSNumber(value: fadeOutStart), 1.0]
                animation.timingFunctions = [easeOut, linear, easeIn]
            } else {
                let peakTime = min(1.0, max(0.0, fadeInEnd))
                animation.values = [0.0, 1.0, 0.0]
                animation.keyTimes = [0.0, NSNumber(value: peakTime), 1.0]
                animation.timingFunctions = [easeOut, easeIn]
            }
        } else if fadeIn > 0 {
            if fadeInEnd < 0.9999 {
                animation.values = [0.0, 1.0, 1.0]
                animation.keyTimes = [0.0, NSNumber(value: fadeInEnd), 1.0]
                animation.timingFunctions = [easeOut, linear]
            } else {
                animation.values = [0.0, 1.0]
                animation.keyTimes = [0.0, 1.0]
                animation.timingFunctions = [easeOut]
            }
        } else if fadeOut > 0 {
            if fadeOutStart > 0.0001 {
                animation.values = [1.0, 1.0, 0.0]
                animation.keyTimes = [0.0, NSNumber(value: fadeOutStart), 1.0]
                animation.timingFunctions = [linear, easeIn]
            } else {
                animation.values = [1.0, 0.0]
                animation.keyTimes = [0.0, 1.0]
                animation.timingFunctions = [easeIn]
            }
        } else {
            animation.values = [1.0, 1.0]
            animation.keyTimes = [0.0, 1.0]
            animation.timingFunctions = [linear]
        }

        return animation
    }
}
