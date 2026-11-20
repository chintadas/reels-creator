import AVFoundation
import QuartzCore
import UIKit

enum OverlayCompositionBuilder {
    static func makeImageOverlayLayer(
        image: CGImage,
        renderSize: CGSize = ReelRenderConfig.renderSize,
        startTimeSeconds: Double,
        durationSeconds: Double,
        fadeInDurationSeconds: Double,
        fadeOutDurationSeconds: Double,
        animationKey: String
    ) -> CALayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contents = image
        overlayLayer.contentsScale = 1.0
        overlayLayer.contentsGravity = .resize
        overlayLayer.opacity = 0.0

        let animation = makeOpacityAnimation(
            startTimeSeconds: startTimeSeconds,
            durationSeconds: durationSeconds,
            fadeInDurationSeconds: fadeInDurationSeconds,
            fadeOutDurationSeconds: fadeOutDurationSeconds
        )
        overlayLayer.add(animation, forKey: animationKey)
        return overlayLayer
    }

    static func makeOpacityAnimation(
        startTimeSeconds: Double,
        durationSeconds: Double,
        fadeInDurationSeconds: Double,
        fadeOutDurationSeconds: Double
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + startTimeSeconds
        animation.duration = durationSeconds
        animation.isRemovedOnCompletion = false

        let fadeIn = max(0, min(fadeInDurationSeconds, durationSeconds))
        let fadeOut = max(0, min(fadeOutDurationSeconds, durationSeconds))
        let fadeInEnd = fadeIn / durationSeconds
        let fadeOutStart = (durationSeconds - fadeOut) / durationSeconds

        // Avoid .both when startTimeSeconds > 0 and opacity starts at 1.0,
        // which would reveal the overlay before beginTime.
        animation.fillMode = (fadeIn > 0 || startTimeSeconds <= 0.0001) ? .both : .forwards

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

    static func makeAnimationTool(
        overlayLayers: [CALayer],
        renderSize: CGSize = ReelRenderConfig.renderSize
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
}
