import AutoFrameCore
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

enum PreviewImageFactory {
    private static let context = CIContext()

    static func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        return context.createCGImage(image, from: rect)
    }
}

