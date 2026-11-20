import CoreMedia
import CoreGraphics
import UIKit

enum ReelRenderConfig {
    static let renderSize = CGSize(width: 1080, height: 1920)
    static let previewCanvasSize = CGSize(width: 360, height: 640)
    static let videoThumbnailMaxSize = CGSize(width: 360, height: 640)
    static let photoThumbnailMaxPixelSize: CGFloat = 640

    static let fps: Int32 = 30
    static let frameDuration = CMTime(value: 1, timescale: fps)
    static let timescale: CMTimeScale = 600

    enum OverlayShadow {
        static let colorAlpha: CGFloat = 0.72
        static let referenceOffsetY: CGFloat = 4.0
        static let referenceBlurRadius: CGFloat = 18.0
    }

    static func aspectFillRect(for contentSize: CGSize, inside container: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return container }
        let scale = max(container.width / contentSize.width, container.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        return CGRect(
            x: container.midX - width / 2.0,
            y: container.midY - height / 2.0,
            width: width,
            height: height
        )
    }

    static func aspectFitRect(for contentSize: CGSize, inside container: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return container }
        let scale = min(container.width / contentSize.width, container.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        return CGRect(
            x: container.midX - width / 2.0,
            y: container.midY - height / 2.0,
            width: width,
            height: height
        )
    }
}
