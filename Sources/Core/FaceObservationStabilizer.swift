import CoreGraphics
import Foundation

public final class FaceObservationStabilizer {
    private var currentFace: DetectedFace?
    private var lastTimestamp: CFTimeInterval?
    private let centerXFilter = OneEuroFilter()
    private let centerYFilter = OneEuroFilter()
    private let widthFilter = OneEuroFilter()
    private let heightFilter = OneEuroFilter()

    public init() {}

    public func reset() {
        currentFace = nil
        lastTimestamp = nil
        centerXFilter.reset()
        centerYFilter.reset()
        widthFilter.reset()
        heightFilter.reset()
    }

    public func ingest(
        _ face: DetectedFace,
        smoothing: Double = 0.82,
        timestamp: CFTimeInterval = CFAbsoluteTimeGetCurrent()
    ) -> DetectedFace {
        guard let currentFace else {
            self.currentFace = face
            lastTimestamp = timestamp
            centerXFilter.seed(face.rect.midX)
            centerYFilter.seed(face.rect.midY)
            widthFilter.seed(face.rect.width)
            heightFilter.seed(face.rect.height)
            return face
        }

        let deltaTime = sanitizedDeltaTime(from: lastTimestamp, to: timestamp)
        lastTimestamp = timestamp
        let configuration = FilterConfiguration(smoothing: smoothing)

        let filteredCenterX = centerXFilter.filter(
            face.rect.midX,
            deltaTime: deltaTime,
            minCutoff: configuration.centerMinCutoff,
            beta: configuration.centerBeta,
            derivativeCutoff: configuration.derivativeCutoff
        )
        let filteredCenterY = centerYFilter.filter(
            face.rect.midY,
            deltaTime: deltaTime,
            minCutoff: configuration.centerMinCutoff,
            beta: configuration.centerBeta,
            derivativeCutoff: configuration.derivativeCutoff
        )
        let filteredWidth = widthFilter.filter(
            face.rect.width,
            deltaTime: deltaTime,
            minCutoff: configuration.sizeMinCutoff,
            beta: configuration.sizeBeta,
            derivativeCutoff: configuration.derivativeCutoff
        )
        let filteredHeight = heightFilter.filter(
            face.rect.height,
            deltaTime: deltaTime,
            minCutoff: configuration.sizeMinCutoff,
            beta: configuration.sizeBeta,
            derivativeCutoff: configuration.derivativeCutoff
        )

        let stabilizedRect = CGRect(
            x: filteredCenterX - (filteredWidth / 2),
            y: filteredCenterY - (filteredHeight / 2),
            width: filteredWidth,
            height: filteredHeight
        ).integral

        let stabilized = DetectedFace(
            rect: stabilizedRect,
            confidence: max(currentFace.confidence * 0.75, face.confidence)
        )
        self.currentFace = stabilized
        return stabilized
    }

    private func sanitizedDeltaTime(from previous: CFTimeInterval?, to current: CFTimeInterval) -> CGFloat {
        guard let previous else { return 1 / 60 }
        return min(max(CGFloat(current - previous), 1 / 240), 1 / 12)
    }
}

private struct FilterConfiguration {
    let centerMinCutoff: CGFloat
    let centerBeta: CGFloat
    let sizeMinCutoff: CGFloat
    let sizeBeta: CGFloat
    let derivativeCutoff: CGFloat

    init(smoothing: Double) {
        let normalized = CGFloat(min(max((smoothing - 0.45) / 0.5, 0), 1))
        centerMinCutoff = Self.interpolate(from: 0.8, to: 0.22, progress: normalized)
        centerBeta = Self.interpolate(from: 0.0052, to: 0.0016, progress: normalized)
        sizeMinCutoff = Self.interpolate(from: 0.7, to: 0.18, progress: normalized)
        sizeBeta = Self.interpolate(from: 0.0028, to: 0.00095, progress: normalized)
        derivativeCutoff = 1
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

private final class OneEuroFilter {
    private var previousValue: CGFloat?
    private var previousFilteredValue: CGFloat?
    private var previousFilteredDerivative: CGFloat = 0

    func reset() {
        previousValue = nil
        previousFilteredValue = nil
        previousFilteredDerivative = 0
    }

    func seed(_ value: CGFloat) {
        previousValue = value
        previousFilteredValue = value
        previousFilteredDerivative = 0
    }

    func filter(
        _ value: CGFloat,
        deltaTime: CGFloat,
        minCutoff: CGFloat,
        beta: CGFloat,
        derivativeCutoff: CGFloat
    ) -> CGFloat {
        guard let previousValue, let previousFilteredValue else {
            seed(value)
            return value
        }

        let derivative = (value - previousValue) / max(deltaTime, 0.0001)
        let derivativeAlpha = alpha(cutoff: derivativeCutoff, deltaTime: deltaTime)
        previousFilteredDerivative = lowPass(
            value: derivative,
            previous: previousFilteredDerivative,
            alpha: derivativeAlpha
        )

        let cutoff = minCutoff + (beta * abs(previousFilteredDerivative))
        let valueAlpha = alpha(cutoff: cutoff, deltaTime: deltaTime)
        let filteredValue = lowPass(value: value, previous: previousFilteredValue, alpha: valueAlpha)

        self.previousValue = value
        self.previousFilteredValue = filteredValue
        return filteredValue
    }

    private func alpha(cutoff: CGFloat, deltaTime: CGFloat) -> CGFloat {
        let safeCutoff = max(cutoff, 0.0001)
        let rate = 2 * .pi * safeCutoff * deltaTime
        return rate / (rate + 1)
    }

    private func lowPass(value: CGFloat, previous: CGFloat, alpha: CGFloat) -> CGFloat {
        previous + (alpha * (value - previous))
    }
}
