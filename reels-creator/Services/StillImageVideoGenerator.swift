import AVFoundation
import Foundation
import ImageIO
import UIKit

enum StillImageVideoGenerator {
    enum GeneratorError: LocalizedError {
        case failedToCreatePixelBuffer
        case failedToRenderImage
        case writerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .failedToCreatePixelBuffer:
                return "Could not allocate video pixel buffer for still image."
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
        let staticPixelBuffer: CVPixelBuffer
        var frameIndex = 0
        var didStartFinishing = false
        var didFinish = false

        init(
            writer: AVAssetWriter,
            input: AVAssetWriterInput,
            adaptor: AVAssetWriterInputPixelBufferAdaptor,
            staticPixelBuffer: CVPixelBuffer
        ) {
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            self.staticPixelBuffer = staticPixelBuffer
        }
    }

    static func generateVideo(
        fromImageAt imageURL: URL,
        durationSeconds: Double,
        outputURL: URL
    ) async throws {
        let reelSize = ReelRenderConfig.renderSize
        let fps = ReelRenderConfig.fps
        let clampedDuration = max(0.2, durationSeconds)
        let totalFrames = max(1, Int(round(clampedDuration * Double(fps))))

        let renderedCGImage = try renderToReelCGImage(imageURL: imageURL, reelSize: reelSize)
        let staticPixelBuffer = try createStaticPixelBuffer(from: renderedCGImage, size: reelSize)

        TemporaryMediaStore.removeItemIfPresent(outputURL)

        do {
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
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
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

            let sessionBox = WriterSessionBox(
                writer: writer,
                input: writerInput,
                adaptor: adaptor,
                staticPixelBuffer: staticPixelBuffer
            )
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
                    guard !sessionBox.didFinish && !sessionBox.didStartFinishing else { return }

                    while sessionBox.input.isReadyForMoreMediaData && sessionBox.frameIndex < totalFrames {
                        let presentationTime = CMTime(
                            value: CMTimeValue(sessionBox.frameIndex),
                            timescale: fps
                        )
                        if !sessionBox.adaptor.append(sessionBox.staticPixelBuffer, withPresentationTime: presentationTime) {
                            sessionBox.didStartFinishing = true
                            sessionBox.input.markAsFinished()
                            sessionBox.writer.cancelWriting()
                            finishOnce(.failure(GeneratorError.writerFailed(sessionBox.writer.error)))
                            return
                        }
                        sessionBox.frameIndex += 1
                    }

                    if sessionBox.frameIndex >= totalFrames && !sessionBox.didStartFinishing {
                        sessionBox.didStartFinishing = true
                        sessionBox.input.markAsFinished()
                        // Explicitly end the session so the last frame gets a full frame duration;
                        // otherwise the track can end at the last frame's PTS (one frame short).
                        sessionBox.writer.endSession(
                            atSourceTime: CMTime(value: CMTimeValue(totalFrames), timescale: fps)
                        )
                        sessionBox.writer.finishWriting {
                            queue.async {
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
        } catch {
            TemporaryMediaStore.removeItemIfPresent(outputURL)
            throw error
        }
    }

    private static func renderToReelCGImage(imageURL: URL, reelSize: CGSize) throws -> CGImage {
        let sourceImage = loadOrientedImage(at: imageURL, targetFillSize: reelSize)
        guard let sourceImage, sourceImage.size.width > 0, sourceImage.size.height > 0 else {
            throw GeneratorError.failedToRenderImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: reelSize, format: format)
        let uiImage = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: reelSize)
            UIColor.black.setFill()
            context.fill(bounds)

            let drawRect = ReelRenderConfig.aspectFillRect(for: sourceImage.size, inside: bounds)
            sourceImage.draw(in: drawRect)
        }

        guard let cgImage = uiImage.cgImage else {
            throw GeneratorError.failedToRenderImage
        }
        return cgImage
    }

    private static func loadOrientedImage(at url: URL, targetFillSize: CGSize) -> UIImage? {
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let rawWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let rawHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           rawWidth > 0,
           rawHeight > 0 {
            let orientationRaw = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
            let isRotated = (5...8).contains(orientationRaw)
            let orientedWidth = isRotated ? rawHeight : rawWidth
            let orientedHeight = isRotated ? rawWidth : rawHeight

            // Compute the minimum pixel max-dimension needed to cover targetFillSize via aspect-fill
            // without losing sharpness on wide panoramic images.
            let fillScale = max(targetFillSize.width / orientedWidth, targetFillSize.height / orientedHeight)
            let requiredMaxDimension = ceil(max(orientedWidth, orientedHeight) * fillScale)

            if max(orientedWidth, orientedHeight) > requiredMaxDimension {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: requiredMaxDimension
                ]
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                    return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
                }
            }
        }

        return UIImage(contentsOfFile: url.path)
    }

    private static func createStaticPixelBuffer(
        from cgImage: CGImage,
        size: CGSize
    ) throws -> CVPixelBuffer {
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = optionalBuffer else {
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

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return pixelBuffer
    }
}
