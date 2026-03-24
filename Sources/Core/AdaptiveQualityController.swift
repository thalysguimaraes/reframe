import Foundation

public enum SegmentationQuality: String, Codable, Sendable {
    case accurate
    case balanced
    case fast
}

public struct AdaptiveProcessingProfile: Equatable, Sendable {
    public let detectionStride: Int
    public let segmentationStride: Int
    public let segmentationQuality: SegmentationQuality
    public let disablesPortraitEffects: Bool
    public let adaptiveQualityActive: Bool

    public static let `default` = AdaptiveProcessingProfile(
        detectionStride: 2,
        segmentationStride: 2,
        segmentationQuality: .accurate,
        disablesPortraitEffects: false,
        adaptiveQualityActive: false
    )
}

public final class AdaptiveQualityController: @unchecked Sendable {
    private var smoothedProcessingDuration: Double = 0
    private var performanceLevel = 0

    public init() {}

    public func reset() {
        smoothedProcessingDuration = 0
        performanceLevel = 0
    }

    public func currentProfile(for settings: AutoFrameSettings, targetFrameRate: Double) -> AdaptiveProcessingProfile {
        let baseDetectionStride = max(settings.detectionStride, 1)
        let baseProfile = AdaptiveProcessingProfile(
            detectionStride: baseDetectionStride,
            segmentationStride: 2,
            segmentationQuality: .accurate,
            disablesPortraitEffects: false,
            adaptiveQualityActive: false
        )

        switch settings.performancePolicy {
        case .fixedQuality:
            return baseProfile
        case .disableHeavyModes:
            let disablesPortrait = performanceLevel >= 2
            return AdaptiveProcessingProfile(
                detectionStride: max(baseDetectionStride, performanceLevel >= 1 ? 3 : baseDetectionStride),
                segmentationStride: performanceLevel >= 1 ? 3 : 2,
                segmentationQuality: performanceLevel >= 1 ? .balanced : .accurate,
                disablesPortraitEffects: disablesPortrait,
                adaptiveQualityActive: performanceLevel > 0
            )
        case .adaptive:
            switch performanceLevel {
            case 2...:
                return AdaptiveProcessingProfile(
                    detectionStride: max(baseDetectionStride, 4),
                    segmentationStride: 4,
                    segmentationQuality: .fast,
                    disablesPortraitEffects: false,
                    adaptiveQualityActive: true
                )
            case 1:
                return AdaptiveProcessingProfile(
                    detectionStride: max(baseDetectionStride, 3),
                    segmentationStride: 3,
                    segmentationQuality: .balanced,
                    disablesPortraitEffects: false,
                    adaptiveQualityActive: true
                )
            default:
                return baseProfile
            }
        }
    }

    public func recordProcessingDuration(
        _ duration: TimeInterval,
        settings: AutoFrameSettings,
        targetFrameRate: Double
    ) {
        guard duration.isFinite, duration > 0 else { return }

        let frameBudget = 1 / max(targetFrameRate, 1)
        let alpha = smoothedProcessingDuration == 0 ? 1.0 : 0.2
        smoothedProcessingDuration = smoothedProcessingDuration == 0
            ? duration
            : ((1 - alpha) * smoothedProcessingDuration) + (alpha * duration)

        switch settings.performancePolicy {
        case .fixedQuality:
            performanceLevel = 0
        case .adaptive, .disableHeavyModes:
            if smoothedProcessingDuration > frameBudget * 1.15 {
                performanceLevel = min(performanceLevel + 1, 2)
            } else if smoothedProcessingDuration < frameBudget * 0.75 {
                performanceLevel = max(performanceLevel - 1, 0)
            }
        }
    }
}
