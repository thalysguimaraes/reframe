import AutoFrameCore
import XCTest

final class AdjustmentValueMappingTests: XCTestCase {
    func testPortraitBlurRadiusStartsAtZeroAndRampsGently() {
        XCTAssertEqual(PortraitBlurMapping.radius(for: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(PortraitBlurMapping.radius(for: 0.25), 2.5, accuracy: 0.0001)
        XCTAssertEqual(PortraitBlurMapping.radius(for: 0.5), 10.0, accuracy: 0.0001)
        XCTAssertEqual(PortraitBlurMapping.radius(for: 1.0), 40.0, accuracy: 0.0001)
    }

    func testPortraitBlurRadiusClampsOutOfBoundsStrength() {
        XCTAssertEqual(PortraitBlurMapping.radius(for: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(PortraitBlurMapping.radius(for: 2), 40.0, accuracy: 0.0001)
    }

    func testContrastControlMappingCentersNeutralAtZero() {
        XCTAssertEqual(ContrastControlMapping.contrast(for: -1.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ContrastControlMapping.contrast(for: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(ContrastControlMapping.contrast(for: 1.0), 2.0, accuracy: 0.0001)

        XCTAssertEqual(ContrastControlMapping.controlValue(for: 0.5), -1.0, accuracy: 0.0001)
        XCTAssertEqual(ContrastControlMapping.controlValue(for: 1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ContrastControlMapping.controlValue(for: 2.0), 1.0, accuracy: 0.0001)
    }

    func testContrastControlMappingRoundTripsIntermediateValues() {
        let controlValues = [-0.75, -0.25, 0.25, 0.75]

        for controlValue in controlValues {
            let contrast = ContrastControlMapping.contrast(for: controlValue)
            XCTAssertEqual(
                ContrastControlMapping.controlValue(for: contrast),
                controlValue,
                accuracy: 0.0001
            )
        }
    }

    func testContrastRelativePercentageUsesNeutralZero() {
        XCTAssertEqual(ContrastControlMapping.relativePercentage(for: 0.5), -50.0, accuracy: 0.0001)
        XCTAssertEqual(ContrastControlMapping.relativePercentage(for: 1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ContrastControlMapping.relativePercentage(for: 2.0), 100.0, accuracy: 0.0001)
    }
}
