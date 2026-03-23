import CoreGraphics
import Foundation

public final class FaceObservationStabilizer {
    private var currentFace: DetectedFace?

    public init() {}

    public func reset() {
        currentFace = nil
    }

    public func ingest(_ face: DetectedFace) -> DetectedFace {
        guard let currentFace else {
            self.currentFace = face
            return face
        }

        let currentCenter = CGPoint(x: currentFace.rect.midX, y: currentFace.rect.midY)
        let incomingCenter = CGPoint(x: face.rect.midX, y: face.rect.midY)
        let centerDistance = hypot(
            incomingCenter.x - currentCenter.x,
            incomingCenter.y - currentCenter.y
        ) / max(currentFace.rect.height, 1)
        let sizeDelta = abs(face.rect.height - currentFace.rect.height) / max(currentFace.rect.height, 1)
        let overlapArea = currentFace.rect.intersection(face.rect).area
        let unionArea = currentFace.rect.area + face.rect.area - overlapArea
        let iou = unionArea > 0 ? overlapArea / unionArea : 0

        let isMinorJitter = iou > 0.72 && centerDistance < 0.18 && sizeDelta < 0.18
        let centerBlend: CGFloat = isMinorJitter ? 0.14 : (centerDistance > 0.45 ? 0.48 : 0.3)
        let sizeBlend: CGFloat = isMinorJitter ? 0.1 : (sizeDelta > 0.35 ? 0.42 : 0.24)

        let stabilizedRect = CGRect(
            x: blend(from: currentFace.rect.minX, to: face.rect.minX, amount: centerBlend),
            y: blend(from: currentFace.rect.minY, to: face.rect.minY, amount: centerBlend),
            width: blend(from: currentFace.rect.width, to: face.rect.width, amount: sizeBlend),
            height: blend(from: currentFace.rect.height, to: face.rect.height, amount: sizeBlend)
        ).integral

        let stabilized = DetectedFace(
            rect: stabilizedRect,
            confidence: max(currentFace.confidence * 0.75, face.confidence)
        )
        self.currentFace = stabilized
        return stabilized
    }

    private func blend(from current: CGFloat, to target: CGFloat, amount: CGFloat) -> CGFloat {
        current + ((target - current) * amount)
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else { return 0 }
        return width * height
    }
}
