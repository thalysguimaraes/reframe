import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

public final class PixelBufferReframer {
    private let context = CIContext()
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    public init() {}

    public func render(pixelBuffer: CVPixelBuffer, cropRect: CGRect, outputSize: CGSize) -> CVPixelBuffer? {
        guard let outputBuffer = makePixelBuffer(size: outputSize) else { return nil }

        // CIImage uses bottom-left origin; crop engine uses top-left origin.
        // Flip the Y coordinate before cropping.
        let sourceHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let flippedRect = CGRect(
            x: cropRect.origin.x,
            y: sourceHeight - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )

        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: flippedRect)
            .transformed(by: CGAffineTransform(translationX: -flippedRect.origin.x, y: -flippedRect.origin.y))
            .transformed(by: CGAffineTransform(
                scaleX: outputSize.width / flippedRect.width,
                y: outputSize.height / flippedRect.height
            ))

        context.render(image, to: outputBuffer)
        return outputBuffer
    }

    private func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            poolSize = size
            pool = createPool(size: size)
        }

        guard let pool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        return pixelBuffer
    }

    private func createPool(size: CGSize) -> CVPixelBufferPool? {
        let attributes: [NSString: Any] = [
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var bufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &bufferPool)
        return bufferPool
    }
}

