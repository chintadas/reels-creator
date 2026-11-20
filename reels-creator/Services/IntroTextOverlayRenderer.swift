import QuartzCore
import ReelsCreatorCore
import UIKit

enum IntroTextOverlayRenderer {
    private struct TextLayoutSpec {
        let attributes: [NSAttributedString.Key: Any]
        let boundingHeight: CGFloat
    }

    static func renderOverlayImage(
        text: String,
        canvasSize: CGSize = ReelRenderConfig.renderSize
    ) -> UIImage? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else {
            return nil
        }

        let scale = canvasSize.width / ReelRenderConfig.renderSize.width
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
        renderSize: CGSize = ReelRenderConfig.renderSize
    ) -> CALayer? {
        guard overlay.durationSeconds > 0,
              let overlayImage = renderOverlayImage(text: overlay.text, canvasSize: renderSize),
              let cgImage = overlayImage.cgImage else {
            return nil
        }

        return OverlayCompositionBuilder.makeImageOverlayLayer(
            image: cgImage,
            renderSize: renderSize,
            startTimeSeconds: overlay.startTimeSeconds,
            durationSeconds: overlay.durationSeconds,
            fadeInDurationSeconds: overlay.fadeInDurationSeconds,
            fadeOutDurationSeconds: overlay.fadeOutDurationSeconds,
            animationKey: "introTextOpacity"
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
        shadow.shadowColor = UIColor.black.withAlphaComponent(ReelRenderConfig.OverlayShadow.colorAlpha)
        shadow.shadowOffset = CGSize(width: 0, height: ReelRenderConfig.OverlayShadow.referenceOffsetY * scale)
        shadow.shadowBlurRadius = ReelRenderConfig.OverlayShadow.referenceBlurRadius * scale

        return [
            .font: font,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]
    }
}
