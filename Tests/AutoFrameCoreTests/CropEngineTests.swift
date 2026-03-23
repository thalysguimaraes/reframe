import AutoFrameCore
import CoreGraphics
import XCTest

final class CropEngineTests: XCTestCase {
    func testTrackingProducesZoomedCrop() {
        let engine = CropEngine()
        let face = DetectedFace(rect: CGRect(x: 800, y: 300, width: 320, height: 320), confidence: 0.95)
        let crop = engine.nextCrop(
            sourceSize: CGSize(width: 3840, height: 2160),
            detectedFace: face,
            settings: .default
        )

        XCTAssertLessThan(crop.width, 3840)
        XCTAssertLessThan(crop.height, 2160)
    }

    func testLostFaceFallsBackTowardWideFrame() {
        let engine = CropEngine()
        let settings = AutoFrameSettings(lostFaceHoldFrames: 1)
        let face = DetectedFace(rect: CGRect(x: 1200, y: 350, width: 280, height: 280), confidence: 0.9)
        _ = engine.nextCrop(sourceSize: CGSize(width: 3840, height: 2160), detectedFace: face, settings: settings)
        let heldCrop = engine.nextCrop(sourceSize: CGSize(width: 3840, height: 2160), detectedFace: nil, settings: settings)
        let widenedCrop = engine.nextCrop(sourceSize: CGSize(width: 3840, height: 2160), detectedFace: nil, settings: settings)

        XCTAssertGreaterThanOrEqual(widenedCrop.width, heldCrop.width)
        XCTAssertGreaterThanOrEqual(widenedCrop.height, heldCrop.height)
    }

    func testLargeFaceOn1080ProducesMinimalZoom() {
        let engine = CropEngine()
        // A 320px face on 1080p is ~30% of frame height — close to the medium
        // preset target of 30%, so zoom should be minimal (near full frame).
        let face = DetectedFace(rect: CGRect(x: 380, y: 260, width: 260, height: 320), confidence: 0.96)
        let crop = engine.nextCrop(
            sourceSize: CGSize(width: 1920, height: 1080),
            detectedFace: face,
            settings: .default
        )

        XCTAssertGreaterThan(crop.height, 1000, "Should barely zoom for a face already near target ratio")
    }

    func testSmallMotionInsideComfortZoneDoesNotRecenter() {
        let engine = CropEngine()
        let source = CGSize(width: 3840, height: 2160)

        let first = DetectedFace(rect: CGRect(x: 1450, y: 580, width: 320, height: 320), confidence: 0.95)
        let second = DetectedFace(rect: CGRect(x: 1480, y: 592, width: 320, height: 320), confidence: 0.95)

        let crop1 = engine.nextCrop(sourceSize: source, detectedFace: first, settings: .default)
        let crop2 = engine.nextCrop(sourceSize: source, detectedFace: second, settings: .default)

        XCTAssertEqual(crop1.midX, crop2.midX, accuracy: 4)
        XCTAssertEqual(crop1.midY, crop2.midY, accuracy: 4)
    }

    func testFaceIsPositionedInUpperThirdNotCentered() {
        let engine = CropEngine()
        let source = CGSize(width: 3840, height: 2160)
        // Face near vertical center of source
        let face = DetectedFace(rect: CGRect(x: 1600, y: 900, width: 300, height: 300), confidence: 0.95)

        // Run several frames so smoothing converges
        var crop = engine.nextCrop(sourceSize: source, detectedFace: face, settings: .default)
        for _ in 0..<30 {
            crop = engine.nextCrop(sourceSize: source, detectedFace: face, settings: .default)
        }

        // Face center (y=1050) should be in the upper portion of the crop, not dead center.
        // With headroomPosition ~0.38, the face center should be above the crop's midY.
        let faceCenterY = face.rect.midY
        let cropMidY = crop.midY
        XCTAssertLessThan(faceCenterY, cropMidY, "Face should sit above crop center (upper-third headroom)")
    }

    func testAsymmetricSmoothingZoomOutIsSlower() {
        let engine = CropEngine()
        let source = CGSize(width: 3840, height: 2160)
        let settings = AutoFrameSettings()

        // Start with a close face, then switch to a distant one (forces zoom out)
        let closeFace = DetectedFace(rect: CGRect(x: 1500, y: 700, width: 400, height: 400), confidence: 0.95)
        let distantFace = DetectedFace(rect: CGRect(x: 1700, y: 850, width: 150, height: 150), confidence: 0.95)

        // Converge on close face
        var crop = engine.nextCrop(sourceSize: source, detectedFace: closeFace, settings: settings)
        for _ in 0..<30 {
            crop = engine.nextCrop(sourceSize: source, detectedFace: closeFace, settings: settings)
        }
        let zoomedInHeight = crop.height

        // One frame toward distant face (should zoom out slowly)
        crop = engine.nextCrop(sourceSize: source, detectedFace: distantFace, settings: settings)
        let zoomOutStep = crop.height - zoomedInHeight

        // Reset and converge on distant face, then zoom in
        let engine2 = CropEngine()
        var crop2 = engine2.nextCrop(sourceSize: source, detectedFace: distantFace, settings: settings)
        for _ in 0..<30 {
            crop2 = engine2.nextCrop(sourceSize: source, detectedFace: distantFace, settings: settings)
        }
        let zoomedOutHeight = crop2.height

        crop2 = engine2.nextCrop(sourceSize: source, detectedFace: closeFace, settings: settings)
        let zoomInStep = zoomedOutHeight - crop2.height

        // Zoom-in step should be larger than zoom-out step (snappier)
        XCTAssertGreaterThan(zoomInStep, zoomOutStep, "Zoom-in should be faster than zoom-out")
    }

    func testHigherZoomStrengthProducesTighterCrop() {
        let face = DetectedFace(rect: CGRect(x: 1450, y: 540, width: 320, height: 320), confidence: 0.95)

        let wideEngine = CropEngine()
        let wideCrop = wideEngine.nextCrop(
            sourceSize: CGSize(width: 3840, height: 2160),
            detectedFace: face,
            settings: AutoFrameSettings(zoomStrength: 0.1)
        )

        let closeEngine = CropEngine()
        let closeCrop = closeEngine.nextCrop(
            sourceSize: CGSize(width: 3840, height: 2160),
            detectedFace: face,
            settings: AutoFrameSettings(zoomStrength: 0.9)
        )

        XCTAssertLessThan(closeCrop.width, wideCrop.width)
        XCTAssertLessThan(closeCrop.height, wideCrop.height)
    }

    func testCrossingHorizontalThresholdDoesNotTriggerLargeSnap() {
        let engine = CropEngine()
        let source = CGSize(width: 3840, height: 2160)
        let stableFace = DetectedFace(rect: CGRect(x: 1500, y: 640, width: 320, height: 320), confidence: 0.95)

        var crop = engine.nextCrop(sourceSize: source, detectedFace: stableFace, settings: .default)
        for _ in 0..<30 {
            crop = engine.nextCrop(sourceSize: source, detectedFace: stableFace, settings: .default)
        }

        let threshold = crop.width * (0.26 * 0.5 + 0.08)
        let shiftedFace = DetectedFace(
            rect: CGRect(
                x: stableFace.rect.origin.x + threshold + 2,
                y: stableFace.rect.origin.y,
                width: stableFace.rect.width,
                height: stableFace.rect.height
            ),
            confidence: 0.95
        )

        let shiftedCrop = engine.nextCrop(sourceSize: source, detectedFace: shiftedFace, settings: .default)

        XCTAssertLessThan(shiftedCrop.midX - crop.midX, 12)
    }

    func testModeratelyOffCenterFaceRecentersHorizontallyAfterConvergence() {
        let engine = CropEngine()
        let source = CGSize(width: 3840, height: 2160)
        let face = DetectedFace(rect: CGRect(x: 2080, y: 720, width: 320, height: 320), confidence: 0.95)

        var crop = engine.nextCrop(sourceSize: source, detectedFace: face, settings: .default)
        for _ in 0..<40 {
            crop = engine.nextCrop(sourceSize: source, detectedFace: face, settings: .default)
        }

        let sourceCenterOffset = abs(face.rect.midX - (source.width / 2))
        let cropCenterOffset = abs(face.rect.midX - crop.midX)

        XCTAssertLessThan(cropCenterOffset, sourceCenterOffset * 0.55)
    }
}
