import AutoFrameCore
import CoreGraphics
import XCTest

final class FaceObservationStabilizerTests: XCTestCase {
    func testMinorFaceJitterGetsHeavilyDamped() {
        let stabilizer = FaceObservationStabilizer()
        let baseline = DetectedFace(rect: CGRect(x: 1000, y: 420, width: 320, height: 320), confidence: 0.92)
        let jittered = DetectedFace(rect: CGRect(x: 1018, y: 430, width: 330, height: 326), confidence: 0.9)

        _ = stabilizer.ingest(baseline, smoothing: 0.9, timestamp: 0)
        let stabilized = stabilizer.ingest(jittered, smoothing: 0.9, timestamp: 1 / 60)

        XCTAssertLessThan(stabilized.rect.minX - baseline.rect.minX, 10)
        XCTAssertLessThan(stabilized.rect.minY - baseline.rect.minY, 8)
        XCTAssertLessThan(stabilized.rect.width - baseline.rect.width, 8)
    }

    func testLargeMovementStillUpdatesTrack() {
        let stabilizer = FaceObservationStabilizer()
        let baseline = DetectedFace(rect: CGRect(x: 900, y: 360, width: 320, height: 320), confidence: 0.92)
        let moved = DetectedFace(rect: CGRect(x: 1320, y: 520, width: 360, height: 360), confidence: 0.94)

        _ = stabilizer.ingest(baseline, smoothing: 0.82, timestamp: 0)
        let stabilized = stabilizer.ingest(moved, smoothing: 0.82, timestamp: 1 / 60)

        XCTAssertGreaterThan(stabilized.rect.midX, baseline.rect.midX + 125)
        XCTAssertGreaterThan(stabilized.rect.midY, baseline.rect.midY + 35)
    }
}
