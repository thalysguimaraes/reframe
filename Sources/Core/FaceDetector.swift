import CoreGraphics
import CoreVideo
import Foundation
import Vision

public final class FaceDetector {
    private let sequenceHandler = VNSequenceRequestHandler()
    private var trackingRequest: VNTrackObjectRequest?

    public init() {}

    public func reset() {
        trackingRequest = nil
    }

    public func observeLargestFace(
        in pixelBuffer: CVPixelBuffer,
        prefersFreshDetection: Bool
    ) throws -> DetectedFace? {
        if prefersFreshDetection || trackingRequest == nil {
            return try detectAndSeedTracking(in: pixelBuffer)
        }

        if let trackedFace = try trackFace(in: pixelBuffer) {
            return trackedFace
        }

        return try detectAndSeedTracking(in: pixelBuffer)
    }

    public func detectLargestFace(in pixelBuffer: CVPixelBuffer) throws -> DetectedFace? {
        guard let observation = try detectLargestFaceObservation(in: pixelBuffer) else {
            return nil
        }

        return face(from: observation, pixelBuffer: pixelBuffer)
    }

    private func detectAndSeedTracking(in pixelBuffer: CVPixelBuffer) throws -> DetectedFace? {
        guard let observation = try detectLargestFaceObservation(in: pixelBuffer) else {
            trackingRequest = nil
            return nil
        }

        let request = VNTrackObjectRequest(detectedObjectObservation: observation)
        request.trackingLevel = .accurate
        trackingRequest = request
        return face(from: observation, pixelBuffer: pixelBuffer)
    }

    private func trackFace(in pixelBuffer: CVPixelBuffer) throws -> DetectedFace? {
        guard let trackingRequest else {
            return nil
        }

        try sequenceHandler.perform([trackingRequest], on: pixelBuffer, orientation: .up)

        guard let observation = trackingRequest.results?.first as? VNDetectedObjectObservation else {
            self.trackingRequest = nil
            return nil
        }

        guard observation.confidence >= 0.35 else {
            self.trackingRequest = nil
            return nil
        }

        trackingRequest.inputObservation = observation
        return face(from: observation, pixelBuffer: pixelBuffer)
    }

    private func detectLargestFaceObservation(in pixelBuffer: CVPixelBuffer) throws -> VNFaceObservation? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        try handler.perform([request])

        return request.results?
            .max(by: { lhs, rhs in lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height })
    }

    private func face(
        from observation: VNDetectedObjectObservation,
        pixelBuffer: CVPixelBuffer
    ) -> DetectedFace {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        let normalized = observation.boundingBox
        let rect = CGRect(
            x: normalized.minX * width,
            y: (1 - normalized.maxY) * height,
            width: normalized.width * width,
            height: normalized.height * height
        ).integral

        return DetectedFace(rect: rect, confidence: observation.confidence)
    }
}
