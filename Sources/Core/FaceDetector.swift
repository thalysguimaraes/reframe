import CoreGraphics
import CoreVideo
import Foundation
import Vision

public final class FaceDetector {
    public init() {}

    public func detectLargestFace(in pixelBuffer: CVPixelBuffer) throws -> DetectedFace? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        try handler.perform([request])

        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let face = request.results?
            .max(by: { lhs, rhs in lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height })

        guard let face else { return nil }

        let normalized = face.boundingBox
        let rect = CGRect(
            x: normalized.minX * width,
            y: (1 - normalized.maxY) * height,
            width: normalized.width * width,
            height: normalized.height * height
        ).integral

        return DetectedFace(rect: rect, confidence: face.confidence)
    }
}
