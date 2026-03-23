import CoreGraphics
import Foundation

/// Crop engine inspired by Apple's Center Stage architecture:
/// - Framing expressed as a zoom factor applied to the source
/// - Face positioned using rule-of-thirds headroom (face eyes ~1/3 from top)
/// - Asymmetric smoothing: zoom-in is snappy, zoom-out is gentle
/// - Comfort zone prevents jitter from small movements
/// - Lost-face fallback gradually widens via a FOV modifier
public final class CropEngine {
    private var currentCrop: CGRect?
    private var consecutiveMisses = 0
    private var lastFaceAnchor: CGPoint?
    private var filteredFaceVelocity = CGVector(dx: 0, dy: 0)

    public init() {}

    public func reset() {
        currentCrop = nil
        consecutiveMisses = 0
        lastFaceAnchor = nil
        filteredFaceVelocity = CGVector(dx: 0, dy: 0)
    }

    public func nextCrop(
        sourceSize: CGSize,
        detectedFace: DetectedFace?,
        settings: AutoFrameSettings
    ) -> CGRect {
        let fullFrame = aspectFittedRect(sourceSize: sourceSize, aspectRatio: settings.outputResolution.aspectRatio)

        guard settings.trackingEnabled else {
            currentCrop = fullFrame
            consecutiveMisses = 0
            return fullFrame
        }

        guard let detectedFace, detectedFace.confidence >= settings.confidenceThreshold else {
            consecutiveMisses += 1
            filteredFaceVelocity = CGVector(
                dx: filteredFaceVelocity.dx * 0.6,
                dy: filteredFaceVelocity.dy * 0.6
            )

            if let currentCrop, consecutiveMisses <= settings.lostFaceHoldFrames {
                return currentCrop
            }

            // Apple uses a faceTrackingFailureFieldOfViewModifier that gradually
            // widens the FOV. We emulate this by smoothing toward full frame
            // with boosted smoothing (slower transition out).
            let widened = smoothRect(
                from: currentCrop ?? fullFrame,
                to: fullFrame,
                smoothing: min(settings.smoothing + 0.08, 0.92),
                isZoomingOut: true
            )
            currentCrop = widened
            return widened
        }

        consecutiveMisses = 0

        let desired = targetRect(
            sourceBounds: fullFrame,
            detectedFace: detectedFace,
            preset: settings.framingPreset,
            zoomStrength: CGFloat(settings.zoomStrength),
            deadZone: CGFloat(settings.deadZone)
        )

        let isZoomingOut = desired.height > (currentCrop ?? fullFrame).height
        let smoothed = smoothRect(
            from: currentCrop ?? fullFrame,
            to: desired,
            smoothing: settings.smoothing,
            isZoomingOut: isZoomingOut
        )
        currentCrop = smoothed
        return smoothed
    }

    public func aspectFittedRect(sourceSize: CGSize, aspectRatio: CGFloat) -> CGRect {
        let sourceAspect = sourceSize.width / sourceSize.height

        if sourceAspect > aspectRatio {
            let width = sourceSize.height * aspectRatio
            let x = (sourceSize.width - width) / 2
            return CGRect(x: x, y: 0, width: width, height: sourceSize.height).integral
        }

        let height = sourceSize.width / aspectRatio
        let y = (sourceSize.height - height) / 2
        return CGRect(x: 0, y: y, width: sourceSize.width, height: height).integral
    }

    // MARK: - Target rect computation

    /// Compute the ideal crop rect for the current face detection.
    ///
    /// Key insight from Center Stage RE: Apple defines framing as a zoom factor
    /// and a center point, not as padding multipliers around the face. The zoom
    /// factor determines how much of the source to show, and the center point
    /// positions the face with proper headroom.
    private func targetRect(
        sourceBounds: CGRect,
        detectedFace: DetectedFace,
        preset: FramingPreset,
        zoomStrength: CGFloat,
        deadZone: CGFloat
    ) -> CGRect {
        let aspectRatio = sourceBounds.width / sourceBounds.height

        // --- Zoom factor from face size ---
        // Compute how zoomed in we should be based on the face's relative size.
        // A larger face in the source = less zoom needed.
        let faceHeightRatio = detectedFace.rect.height / sourceBounds.height
        let faceWidthRatio = detectedFace.rect.width / sourceBounds.width

        // Target: face should occupy a fraction of the crop height defined by the preset.
        // For medium: face ~18% of crop height -> natural talking-head framing.
        let targetFaceRatio = preset.targetFaceHeightRatio * zoomFaceRatioMultiplier(for: zoomStrength)
        let zoomFromHeight = faceHeightRatio / targetFaceRatio
        let zoomFromWidth = faceWidthRatio / (targetFaceRatio * 0.8)
        let rawZoom = max(zoomFromHeight, zoomFromWidth)

        // Clamp zoom to preset bounds
        let effectiveMaxZoomScale = preset.maxZoomScale * zoomTightnessMultiplier(for: zoomStrength)
        let zoom = clamp(value: rawZoom, minValue: 1.0 / effectiveMaxZoomScale, maxValue: 1.0)

        let cropHeight = sourceBounds.height * zoom
        let cropWidth = cropHeight * aspectRatio

        // --- Face positioning with headroom ---
        // Apple positions the face using a "rule of thirds" approach.
        // The face center should sit at roughly 38-42% from the top of the crop
        // (i.e., slightly above center, with more space above for headroom).
        let faceCenter = CGPoint(x: detectedFace.rect.midX, y: detectedFace.rect.midY)

        updateFaceMotion(anchorPoint: faceCenter)

        // Where in the crop should the face center be? (0 = top, 1 = bottom)
        // Adjust based on face size: close-up faces need less headroom shift
        let headroomPosition = max(
            0.34,
            preset.headroomPosition
                + (faceHeightRatio > 0.25 ? 0.04 : 0.0)
                - ((zoomStrength - 0.5) * 0.04)
        )

        // Desired crop center: position face at headroomPosition within the crop
        var cropCenterY = faceCenter.y - (headroomPosition - 0.5) * cropHeight
        var cropCenterX = faceCenter.x

        // Apply comfort zone stabilization
        let previous = currentCrop ?? sourceBounds
        let stabilized = stabilizedCenter(
            previousCrop: previous,
            anchorPoint: CGPoint(x: cropCenterX, y: cropCenterY),
            preset: preset,
            deadZone: deadZone
        )
        cropCenterX = stabilized.x
        cropCenterY = stabilized.y

        // Subtle look-ahead from face velocity
        cropCenterX += clamp(
            value: filteredFaceVelocity.dx * preset.lookAheadFactorX,
            minValue: -sourceBounds.width * 0.008,
            maxValue: sourceBounds.width * 0.008
        )
        cropCenterY += clamp(
            value: filteredFaceVelocity.dy * preset.lookAheadFactorY,
            minValue: -sourceBounds.height * 0.01,
            maxValue: sourceBounds.height * 0.01
        )

        // Build and clamp rect
        var rect = CGRect(
            x: cropCenterX - cropWidth / 2,
            y: cropCenterY - cropHeight / 2,
            width: cropWidth,
            height: cropHeight
        )
        rect = clampRect(rect, within: sourceBounds)
        return rect.integral
    }

    // MARK: - Stabilization

    private func stabilizedCenter(
        previousCrop: CGRect,
        anchorPoint: CGPoint,
        preset: FramingPreset,
        deadZone: CGFloat
    ) -> CGPoint {
        let comfortHalfWidth = previousCrop.width * preset.comfortZoneWidthRatio * 0.5
        let comfortHalfHeight = previousCrop.height * preset.comfortZoneHeightRatio * 0.5
        let deadZoneX = previousCrop.width * deadZone * 0.35
        let deadZoneY = previousCrop.height * deadZone

        var center = CGPoint(x: previousCrop.midX, y: previousCrop.midY)
        let thresholdX = comfortHalfWidth + deadZoneX
        let thresholdY = comfortHalfHeight + deadZoneY
        let offsetX = anchorPoint.x - center.x
        let offsetY = anchorPoint.y - center.y

        if offsetX < -thresholdX {
            center.x += offsetX + thresholdX
        } else if offsetX > thresholdX {
            center.x += offsetX - thresholdX
        }

        if offsetY < -thresholdY {
            center.y += offsetY + thresholdY
        } else if offsetY > thresholdY {
            center.y += offsetY - thresholdY
        }

        return center
    }

    private func updateFaceMotion(anchorPoint: CGPoint) {
        guard let lastFaceAnchor else {
            lastFaceAnchor = anchorPoint
            filteredFaceVelocity = CGVector(dx: 0, dy: 0)
            return
        }

        let rawVelocity = CGVector(
            dx: anchorPoint.x - lastFaceAnchor.x,
            dy: anchorPoint.y - lastFaceAnchor.y
        )
        let velocityBlend: CGFloat = 0.35
        filteredFaceVelocity = CGVector(
            dx: filteredFaceVelocity.dx * (1 - velocityBlend) + rawVelocity.dx * velocityBlend,
            dy: filteredFaceVelocity.dy * (1 - velocityBlend) + rawVelocity.dy * velocityBlend
        )
        self.lastFaceAnchor = anchorPoint
    }

    // MARK: - Asymmetric smoothing

    /// Smoothing inspired by Apple's `rampExponentiallyToVideoZoomFactor:withDuration:`
    ///
    /// Key RE insight: Apple uses separate ramp types and tuning for zoom-in vs zoom-out.
    /// Zoom-in (framing tightens) should be snappier so you don't lose the subject.
    /// Zoom-out (framing widens) should be gentler so the frame doesn't jerk open.
    /// Position smoothing gets a distance-proportional boost so large movements
    /// are tracked faster.
    private func smoothRect(
        from current: CGRect,
        to target: CGRect,
        smoothing: Double,
        isZoomingOut: Bool
    ) -> CGRect {
        let baseGain = max(0.06, 1 - smoothing)

        // Asymmetric: zoom-in is ~2x faster than zoom-out
        let sizeGain: CGFloat
        if isZoomingOut {
            sizeGain = clamp(value: baseGain * 0.45, minValue: 0.03, maxValue: 0.15)
        } else {
            sizeGain = clamp(value: baseGain + 0.08, minValue: 0.08, maxValue: 0.30)
        }

        // Position gain scales with distance so large movements converge faster
        let currentCenter = CGPoint(x: current.midX, y: current.midY)
        let targetCenter = CGPoint(x: target.midX, y: target.midY)
        let centerDistance = hypot(targetCenter.x - currentCenter.x, targetCenter.y - currentCenter.y)
        let normalizedDistance = centerDistance / max(current.width, 1)
        let distanceBoost = clamp(value: normalizedDistance * 0.5, minValue: 0, maxValue: 0.15)
        let centerGain = clamp(
            value: baseGain + distanceBoost,
            minValue: 0.06,
            maxValue: 0.28
        )

        // Step limits prevent single-frame jumps
        let maxCenterStepX = current.width * 0.10
        let maxCenterStepY = current.height * 0.08
        let maxSizeStep = current.height * 0.08

        let deltaX = clamp(
            value: (targetCenter.x - currentCenter.x) * centerGain,
            minValue: -maxCenterStepX,
            maxValue: maxCenterStepX
        )
        let deltaY = clamp(
            value: (targetCenter.y - currentCenter.y) * centerGain,
            minValue: -maxCenterStepY,
            maxValue: maxCenterStepY
        )
        let deltaHeight = clamp(
            value: (target.height - current.height) * sizeGain,
            minValue: -maxSizeStep,
            maxValue: maxSizeStep
        )

        let nextHeight = max(target.height * 0.25, current.height + deltaHeight)
        let nextWidth = nextHeight * (target.width / max(target.height, 1))
        let center = CGPoint(x: currentCenter.x + deltaX, y: currentCenter.y + deltaY)

        return CGRect(
            x: center.x - nextWidth / 2,
            y: center.y - nextHeight / 2,
            width: nextWidth,
            height: nextHeight
        ).integral
    }

    // MARK: - Helpers

    private func clampRect(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        var r = rect.standardized
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    private func zoomFaceRatioMultiplier(for zoomStrength: CGFloat) -> CGFloat {
        clamp(
            value: 1 + ((zoomStrength - 0.5) * 0.75),
            minValue: 0.65,
            maxValue: 1.35
        )
    }

    private func zoomTightnessMultiplier(for zoomStrength: CGFloat) -> CGFloat {
        clamp(
            value: 1 + ((zoomStrength - 0.5) * 0.8),
            minValue: 0.75,
            maxValue: 1.4
        )
    }

    private func clamp<T: Comparable>(value: T, minValue: T, maxValue: T) -> T {
        min(max(value, minValue), maxValue)
    }
}
