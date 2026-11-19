import AVFoundation
import Foundation
import UIKit

enum StillImageLayoutMode {
    /// Static aspect-fill center crop to 1080x1920 (no Ken Burns motion).
    case aspectFillCrop
    /// Aspect-fit centered inside 1080x1920 over a solid branded background color.
    case aspectFitCentered(backgroundColor: UIColor)
}

enum StillImageVideoGenerator {
    enum GeneratorError: LocalizedError {
        case failedToCreatePixelBuffer
        case failedToCreatePixelBufferPool
        case failedToRenderImage
        case writerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .failedToCreatePixelBuffer:
                return "Could not allocate video pixel buffer for still image."
            case .failedToCreatePixelBufferPool:
                return "Could not initialize AVAssetWriter pixel buffer pool."
            case .failedToRenderImage:
                return "Could not render still image into 9:16 frame."
            case .writerFailed(let error):
                return "Video writer failed: \(error?.localizedDescription ?? "Unknown error")"
            }
        }
    }

    private final class WriterSessionBox: @unchecked Sendable {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        var frameIndex = 0
        var didFinish = false

        init(
            writer: AVAssetWriter,
            input: AVAssetWriterInput,
            adaptor: AVAssetWriterInputPixelBufferAdaptor
        ) {
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
        }
    }

    static let reelSize = CGSize(width: 1080, height: 1920)
    static let fps: Int32 = 30

    static func generateVideo(
        from image: UIImage,
        durationSeconds: Double,
        layoutMode: StillImageLayoutMode,
        outputURL: URL
    ) async throws {
        let clampedDuration = max(0.2, durationSeconds)
        let totalFrames = max(1, Int(round(clampedDuration * Double(fps))))
        let renderedCGImage = try renderToReelCGImage(image: image, layoutMode: layoutMode)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(reelSize.width),
            AVVideoHeightKey: Int(reelSize.height)
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(reelSize.width),
            kCVPixelBufferHeightKey as String: Int(reelSize.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw GeneratorError.writerFailed(nil)
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw GeneratorError.writerFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        let sessionBox = WriterSessionBox(writer: writer, input: writerInput, adaptor: adaptor)
        let queue = DispatchQueue(label: "com.schintada.reels-creator.still-video-writer")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let finishOnce: @Sendable (Result<Void, Error>) -> Void = { result in
                guard !sessionBox.didFinish else { return }
                sessionBox.didFinish = true
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            sessionBox.input.requestMediaDataWhenReady(on: queue) {
                while sessionBox.input.isReadyForMoreMediaData && sessionBox.frameIndex < totalFrames {
                    do {
                        let pixelBuffer = try createPixelBuffer(
                            from: renderedCGImage,
                            pool: sessionBox.adaptor.pixelBufferPool
                        )
                        let presentationTime = CMTime(
                            value: CMTimeValue(sessionBox.frameIndex),
                            timescale: fps
                        )
                        if !sessionBox.adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                            throw GeneratorError.writerFailed(sessionBox.writer.error)
                        }
                        sessionBox.frameIndex += 1
                    } catch {
                        sessionBox.input.markAsFinished()
                        sessionBox.writer.cancelWriting()
                        finishOnce(.failure(error))
                        return
                    }
                }

                if sessionBox.frameIndex >= totalFrames {
                    sessionBox.input.markAsFinished()
                    // Explicitly end the session so the last frame gets a full frame duration;
                    // otherwise the track can end at the last frame's PTS (one frame short).
                    sessionBox.writer.endSession(
                        atSourceTime: CMTime(value: CMTimeValue(totalFrames), timescale: fps)
                    )
                    sessionBox.writer.finishWriting {
                        if sessionBox.writer.status == .completed {
                            finishOnce(.success(()))
                        } else {
                            finishOnce(.failure(GeneratorError.writerFailed(sessionBox.writer.error)))
                        }
                    }
                }
            }
        }
    }

    private static func renderToReelCGImage(
        image: UIImage,
        layoutMode: StillImageLayoutMode
    ) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: reelSize, format: format)
        let uiImage = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: reelSize)

            switch layoutMode {
            case .aspectFillCrop:
                UIColor.black.setFill()
                context.fill(bounds)

                let drawRect = aspectFillRect(for: image.size, inside: bounds)
                image.draw(in: drawRect)

            case .aspectFitCentered(let backgroundColor):
                backgroundColor.setFill()
                context.fill(bounds)

                let paddedBounds = bounds.insetBy(dx: 140, dy: 240)
                let drawRect = aspectFitRect(for: image.size, inside: paddedBounds)
                image.draw(in: drawRect)
            }
        }

        guard let cgImage = uiImage.cgImage else {
            throw GeneratorError.failedToRenderImage
        }
        return cgImage
    }

    private static func createPixelBuffer(
        from cgImage: CGImage,
        pool: CVPixelBufferPool?
    ) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?

        if let pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer)
            if status != kCVReturnSuccess {
                throw GeneratorError.failedToCreatePixelBufferPool
            }
        } else {
            let attributes: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(reelSize.width),
                Int(reelSize.height),
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &optionalBuffer
            )
            if status != kCVReturnSuccess {
                throw GeneratorError.failedToCreatePixelBuffer
            }
        }

        guard let pixelBuffer = optionalBuffer else {
            throw GeneratorError.failedToCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw GeneratorError.failedToCreatePixelBuffer
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        guard let context = CGContext(
            data: baseAddress,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw GeneratorError.failedToCreatePixelBuffer
        }

        context.draw(cgImage, in: CGRect(origin: .zero, size: reelSize))
        return pixelBuffer
    }

    private static func aspectFillRect(for imageSize: CGSize, inside container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = max(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: container.midX - width / 2.0,
            y: container.midY - height / 2.0,
            width: width,
            height: height
        )
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
