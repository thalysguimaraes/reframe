import AutoFrameCore
import CoreMedia
import XCTest

final class CaptureFormatSelectorTests: XCTestCase {
    func testPrefersSmallestFormatThatMeetsResolutionAnd60FPS() {
        let settings = AutoFrameSettings(outputResolution: .hd1080)
        let descriptors = [
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 3840, height: 2160),
                maxFrameRate: 60,
                position: 0
            ),
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 1920, height: 1080),
                maxFrameRate: 60,
                position: 1
            ),
        ]

        let selection = CaptureFormatSelector.selectBestFormat(from: descriptors, for: settings)

        XCTAssertEqual(selection?.descriptor.position, 1)
        XCTAssertEqual(selection?.targetFrameRate, 60)
    }

    func testFallsBackToThirtyFPSWhenSixtyIsUnavailable() {
        let settings = AutoFrameSettings(outputResolution: .hd1080)
        let descriptors = [
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 1920, height: 1080),
                maxFrameRate: 30,
                position: 0
            ),
        ]

        let selection = CaptureFormatSelector.selectBestFormat(from: descriptors, for: settings)

        XCTAssertEqual(selection?.descriptor.position, 0)
        XCTAssertEqual(selection?.targetFrameRate, 30)
    }

    func testUsesActualSupportedFrameRateWhenFormatIsJustBelowSixtyFPS() {
        let settings = AutoFrameSettings(outputResolution: .hd1080)
        let descriptors = [
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 1920, height: 1080),
                maxFrameRate: 59.94,
                position: 0
            ),
        ]

        let selection = CaptureFormatSelector.selectBestFormat(from: descriptors, for: settings)

        XCTAssertEqual(selection?.descriptor.position, 0)
        XCTAssertNotNil(selection)
        XCTAssertEqual(selection!.targetFrameRate, 59.94, accuracy: 0.001)
    }

    func testFrameDurationPreservesFractionalFrameRates() {
        let duration = OutputResolution.hd1080.frameDuration(for: 59.94)

        XCTAssertEqual(CMTimeGetSeconds(duration), 1 / 59.94, accuracy: 0.000_001)
    }

    func testPrefersDedicatedThirtyFPSFormatWhenFallingBack() {
        let settings = AutoFrameSettings(outputResolution: .hd1080)
        let descriptors = [
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 1920, height: 1080),
                maxFrameRate: 60,
                position: 0
            ),
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 1920, height: 1080),
                maxFrameRate: 30,
                position: 1
            ),
        ]

        let selection = CaptureFormatSelector.selectBestFormat(
            from: descriptors,
            for: settings,
            preferredFrameRate: 30
        )

        XCTAssertEqual(selection?.descriptor.position, 1)
        XCTAssertEqual(selection?.targetFrameRate, 30)
    }

    func testRejectsFormatsBelowThirtyFPS() {
        let settings = AutoFrameSettings(outputResolution: .hd1080)
        let descriptors = [
            CaptureFormatDescriptor(
                dimensions: CMVideoDimensions(width: 1920, height: 1080),
                maxFrameRate: 24,
                position: 0
            ),
        ]

        XCTAssertNil(CaptureFormatSelector.selectBestFormat(from: descriptors, for: settings))
    }
}
