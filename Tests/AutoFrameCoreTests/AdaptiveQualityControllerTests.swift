import AutoFrameCore
import XCTest

final class AdaptiveQualityControllerTests: XCTestCase {
    func testAdaptiveProfileEscalatesUnderSustainedLoad() {
        let controller = AdaptiveQualityController()
        let settings = AutoFrameSettings(detectionStride: 2, performancePolicy: .adaptive)

        for _ in 0..<8 {
            controller.recordProcessingDuration(0.030, settings: settings, targetFrameRate: 60)
        }

        let profile = controller.currentProfile(for: settings, targetFrameRate: 60)

        XCTAssertTrue(profile.adaptiveQualityActive)
        XCTAssertGreaterThanOrEqual(profile.detectionStride, 3)
        XCTAssertGreaterThanOrEqual(profile.segmentationStride, 3)
    }

    func testAdaptiveProfileRecoversWhenLoadDrops() {
        let controller = AdaptiveQualityController()
        let settings = AutoFrameSettings(detectionStride: 2, performancePolicy: .adaptive)

        for _ in 0..<8 {
            controller.recordProcessingDuration(0.030, settings: settings, targetFrameRate: 60)
        }
        for _ in 0..<12 {
            controller.recordProcessingDuration(0.006, settings: settings, targetFrameRate: 60)
        }

        let profile = controller.currentProfile(for: settings, targetFrameRate: 60)

        XCTAssertFalse(profile.adaptiveQualityActive)
        XCTAssertEqual(profile.detectionStride, 2)
        XCTAssertEqual(profile.segmentationStride, 2)
        XCTAssertEqual(profile.segmentationQuality, .accurate)
    }

    func testFixedQualityPolicyNeverDegrades() {
        let controller = AdaptiveQualityController()
        let settings = AutoFrameSettings(detectionStride: 2, performancePolicy: .fixedQuality)

        for _ in 0..<10 {
            controller.recordProcessingDuration(0.050, settings: settings, targetFrameRate: 60)
        }

        let profile = controller.currentProfile(for: settings, targetFrameRate: 60)

        XCTAssertFalse(profile.adaptiveQualityActive)
        XCTAssertEqual(profile.detectionStride, 2)
        XCTAssertEqual(profile.segmentationStride, 2)
        XCTAssertEqual(profile.segmentationQuality, .accurate)
    }
}
