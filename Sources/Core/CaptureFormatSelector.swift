import CoreMedia
import Foundation

public struct CaptureFormatDescriptor: Sendable {
    public let dimensions: CMVideoDimensions
    public let maxFrameRate: Double
    public let position: Int

    public init(dimensions: CMVideoDimensions, maxFrameRate: Double, position: Int) {
        self.dimensions = dimensions
        self.maxFrameRate = maxFrameRate
        self.position = position
    }
}

public struct CaptureFormatSelection: Sendable {
    public let descriptor: CaptureFormatDescriptor
    public let targetFrameRate: Double
}

public enum CaptureFormatSelector {
    public static func selectBestFormat(
        from descriptors: [CaptureFormatDescriptor],
        for settings: AutoFrameSettings,
        preferredFrameRate: Double? = nil
    ) -> CaptureFormatSelection? {
        let preferredFrameRate = preferredFrameRate ?? settings.outputResolution.preferredFrameRate
        let fallbackFrameRate = settings.outputResolution.fallbackFrameRate
        let preferredFrameRateThreshold = preferredFrameRate - 0.5
        let requiredWidth = Int32(settings.outputResolution.size.width.rounded())
        let requiredHeight = Int32(settings.outputResolution.size.height.rounded())
        let desiredFrameRate = descriptors.contains {
            $0.dimensions.width >= requiredWidth &&
                $0.dimensions.height >= requiredHeight &&
                $0.maxFrameRate >= preferredFrameRateThreshold
        }
            ? preferredFrameRate
            : fallbackFrameRate

        let sortedDescriptors = descriptors.sorted { lhs, rhs in
            score(
                lhs,
                requiredWidth: requiredWidth,
                requiredHeight: requiredHeight,
                desiredFrameRate: desiredFrameRate
            ) < score(
                rhs,
                requiredWidth: requiredWidth,
                requiredHeight: requiredHeight,
                desiredFrameRate: desiredFrameRate
            )
        }

        guard let descriptor = sortedDescriptors.first else {
            return nil
        }

        let targetFrameRate = descriptor.maxFrameRate >= preferredFrameRateThreshold
            ? min(descriptor.maxFrameRate, preferredFrameRate)
            : min(descriptor.maxFrameRate, fallbackFrameRate)
        guard targetFrameRate >= fallbackFrameRate else {
            return nil
        }

        return CaptureFormatSelection(descriptor: descriptor, targetFrameRate: targetFrameRate)
    }

    private static func score(
        _ descriptor: CaptureFormatDescriptor,
        requiredWidth: Int32,
        requiredHeight: Int32,
        desiredFrameRate: Double
    ) -> (Int, Int, Int64, Int64, Int) {
        let meetsResolution = descriptor.dimensions.width >= requiredWidth && descriptor.dimensions.height >= requiredHeight
        let meetsDesiredFrameRate = descriptor.maxFrameRate >= desiredFrameRate - 0.5
        let pixelArea = Int64(descriptor.dimensions.width) * Int64(descriptor.dimensions.height)
        let frameRateOverage = Int64((max(descriptor.maxFrameRate - desiredFrameRate, 0) * 1_000).rounded())

        return (
            meetsResolution ? 0 : 1,
            meetsDesiredFrameRate ? 0 : 1,
            pixelArea,
            frameRateOverage,
            descriptor.position
        )
    }
}
