import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

public enum FramingPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case tight
    case medium
    case wide

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    /// What fraction of the crop height the face should occupy.
    /// Larger = more zoomed in. At desk distance on 4K, a typical face is
    /// ~18-22% of source height. These values ensure meaningful zoom.
    var targetFaceHeightRatio: CGFloat {
        switch self {
        case .tight:
            return 0.38
        case .medium:
            return 0.30
        case .wide:
            return 0.22
        }
    }

    /// Where the face center should sit vertically in the crop (0=top, 1=bottom).
    /// ~0.38 puts the eyes near the upper third line — natural talking-head framing.
    var headroomPosition: CGFloat {
        switch self {
        case .tight:
            return 0.40
        case .medium:
            return 0.38
        case .wide:
            return 0.36
        }
    }

    var comfortZoneWidthRatio: CGFloat {
        switch self {
        case .tight:
            return 0.12
        case .medium:
            return 0.16
        case .wide:
            return 0.22
        }
    }

    var comfortZoneHeightRatio: CGFloat {
        switch self {
        case .tight:
            return 0.16
        case .medium:
            return 0.20
        case .wide:
            return 0.24
        }
    }

    var lookAheadFactorX: CGFloat {
        switch self {
        case .tight:
            return 0.20
        case .medium:
            return 0.14
        case .wide:
            return 0.10
        }
    }

    var lookAheadFactorY: CGFloat {
        switch self {
        case .tight:
            return 0.12
        case .medium:
            return 0.1
        case .wide:
            return 0.08
        }
    }

    var maxZoomScale: CGFloat {
        switch self {
        case .tight:
            return 3.2
        case .medium:
            return 2.6
        case .wide:
            return 2.0
        }
    }
}

public enum OutputResolution: String, CaseIterable, Codable, Identifiable, Sendable {
    case hd720 = "720p"
    case hd1080 = "1080p"

    public var id: String { rawValue }

    public var size: CGSize {
        switch self {
        case .hd720:
            return CGSize(width: 1280, height: 720)
        case .hd1080:
            return CGSize(width: 1920, height: 1080)
        }
    }

    public var preferredFrameRate: Double {
        60
    }

    public var fallbackFrameRate: Double {
        30
    }

    public var supportedFrameRates: [Double] {
        [preferredFrameRate, fallbackFrameRate]
    }

    public var frameDuration: CMTime {
        frameDuration(for: preferredFrameRate)
    }

    public func frameDuration(for frameRate: Double) -> CMTime {
        let sanitizedFrameRate = max(frameRate, 1)
        return CMTimeMakeWithSeconds(1 / sanitizedFrameRate, preferredTimescale: 60_000)
    }

    public var aspectRatio: CGFloat {
        size.width / size.height
    }

    public var displayName: String {
        rawValue
    }
}

public enum PerformancePolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case adaptive
    case fixedQuality
    case disableHeavyModes

    public var id: String { rawValue }
}

public enum GradientPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case warmSunset
    case coolOcean
    case softLavender

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warmSunset: return "Sunset"
        case .coolOcean: return "Ocean"
        case .softLavender: return "Lavender"
        }
    }
}

public enum VirtualBackgroundMode: String, Codable, Equatable, Sendable {
    case off
    case gradient
    case customImage
}

public struct CustomBackground: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var fileName: String

    public init(id: String = UUID().uuidString, name: String, fileName: String) {
        self.id = id
        self.name = name
        self.fileName = fileName
    }
}

public struct AutoFrameSettings: Codable, Equatable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var cameraID: String?
    public var outputResolution: OutputResolution
    public var framingPreset: FramingPreset
    public var smoothing: Double
    public var zoomStrength: Double
    public var deadZone: Double
    public var trackingEnabled: Bool
    public var detectionStride: Int
    public var lostFaceHoldFrames: Int
    public var confidenceThreshold: Float
    public var portraitModeEnabled: Bool
    public var portraitBlurStrength: Double
    public var virtualBackgroundMode: VirtualBackgroundMode
    public var virtualBackgroundGradient: GradientPreset
    public var customBackgrounds: [CustomBackground]
    public var selectedCustomBackgroundID: String?
    public var performancePolicy: PerformancePolicy
    public var exposure: Double
    public var contrast: Double
    public var temperature: Double
    public var tint: Double
    public var vibrance: Double
    public var saturation: Double
    public var sharpness: Double
    public var showInMenuBar: Bool
    public var showDockIcon: Bool
    public var keepRunningOnClose: Bool

    public init(
        hasCompletedOnboarding: Bool = false,
        cameraID: String? = nil,
        outputResolution: OutputResolution = .hd1080,
        framingPreset: FramingPreset = .medium,
        smoothing: Double = 0.82,
        zoomStrength: Double = 0.5,
        deadZone: Double = 0.08,
        trackingEnabled: Bool = true,
        detectionStride: Int = 2,
        lostFaceHoldFrames: Int = 24,
        confidenceThreshold: Float = 0.4,
        portraitModeEnabled: Bool = false,
        portraitBlurStrength: Double = 0.5,
        virtualBackgroundMode: VirtualBackgroundMode = .off,
        virtualBackgroundGradient: GradientPreset = .warmSunset,
        customBackgrounds: [CustomBackground] = [],
        selectedCustomBackgroundID: String? = nil,
        performancePolicy: PerformancePolicy = .adaptive,
        exposure: Double = 0.0,
        contrast: Double = 1.0,
        temperature: Double = 6500.0,
        tint: Double = 0.0,
        vibrance: Double = 0.0,
        saturation: Double = 1.0,
        sharpness: Double = 0.0,
        showInMenuBar: Bool = true,
        showDockIcon: Bool = true,
        keepRunningOnClose: Bool = true
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.cameraID = cameraID
        self.outputResolution = outputResolution
        self.framingPreset = framingPreset
        self.smoothing = smoothing
        self.zoomStrength = zoomStrength
        self.deadZone = deadZone
        self.trackingEnabled = trackingEnabled
        self.detectionStride = detectionStride
        self.lostFaceHoldFrames = lostFaceHoldFrames
        self.confidenceThreshold = confidenceThreshold
        self.portraitModeEnabled = portraitModeEnabled
        self.portraitBlurStrength = portraitBlurStrength
        self.virtualBackgroundMode = virtualBackgroundMode
        self.virtualBackgroundGradient = virtualBackgroundGradient
        self.customBackgrounds = customBackgrounds
        self.selectedCustomBackgroundID = selectedCustomBackgroundID
        self.performancePolicy = performancePolicy
        self.exposure = exposure
        self.contrast = contrast
        self.temperature = temperature
        self.tint = tint
        self.vibrance = vibrance
        self.saturation = saturation
        self.sharpness = sharpness
        self.showInMenuBar = showInMenuBar
        self.showDockIcon = showDockIcon
        self.keepRunningOnClose = keepRunningOnClose
    }

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, cameraID, outputResolution, framingPreset, smoothing, zoomStrength, deadZone
        case trackingEnabled, detectionStride, lostFaceHoldFrames, confidenceThreshold
        case portraitModeEnabled, portraitBlurStrength
        case virtualBackgroundMode, virtualBackgroundGradient, customBackgrounds, selectedCustomBackgroundID
        case performancePolicy
        case exposure, contrast, temperature, tint, vibrance, saturation, sharpness
        case showInMenuBar, showDockIcon, keepRunningOnClose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        cameraID = try container.decodeIfPresent(String.self, forKey: .cameraID)
        outputResolution = try container.decodeIfPresent(OutputResolution.self, forKey: .outputResolution) ?? .hd1080
        framingPreset = try container.decodeIfPresent(FramingPreset.self, forKey: .framingPreset) ?? .medium
        smoothing = try container.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.82
        zoomStrength = try container.decodeIfPresent(Double.self, forKey: .zoomStrength) ?? 0.5
        deadZone = try container.decodeIfPresent(Double.self, forKey: .deadZone) ?? 0.08
        trackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .trackingEnabled) ?? true
        detectionStride = try container.decodeIfPresent(Int.self, forKey: .detectionStride) ?? 2
        lostFaceHoldFrames = try container.decodeIfPresent(Int.self, forKey: .lostFaceHoldFrames) ?? 24
        confidenceThreshold = try container.decodeIfPresent(Float.self, forKey: .confidenceThreshold) ?? 0.4
        portraitModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .portraitModeEnabled) ?? false
        portraitBlurStrength = try container.decodeIfPresent(Double.self, forKey: .portraitBlurStrength) ?? 0.5
        virtualBackgroundMode = try container.decodeIfPresent(VirtualBackgroundMode.self, forKey: .virtualBackgroundMode) ?? .off
        virtualBackgroundGradient = try container.decodeIfPresent(GradientPreset.self, forKey: .virtualBackgroundGradient) ?? .warmSunset
        customBackgrounds = try container.decodeIfPresent([CustomBackground].self, forKey: .customBackgrounds) ?? []
        selectedCustomBackgroundID = try container.decodeIfPresent(String.self, forKey: .selectedCustomBackgroundID)
        performancePolicy = try container.decodeIfPresent(PerformancePolicy.self, forKey: .performancePolicy) ?? .adaptive
        exposure = try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0.0
        contrast = try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 1.0
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 6500.0
        tint = try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0.0
        vibrance = try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0.0
        saturation = try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 1.0
        sharpness = try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0.0
        showInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? true
        keepRunningOnClose = try container.decodeIfPresent(Bool.self, forKey: .keepRunningOnClose) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encodeIfPresent(cameraID, forKey: .cameraID)
        try container.encode(outputResolution, forKey: .outputResolution)
        try container.encode(framingPreset, forKey: .framingPreset)
        try container.encode(smoothing, forKey: .smoothing)
        try container.encode(zoomStrength, forKey: .zoomStrength)
        try container.encode(deadZone, forKey: .deadZone)
        try container.encode(trackingEnabled, forKey: .trackingEnabled)
        try container.encode(detectionStride, forKey: .detectionStride)
        try container.encode(lostFaceHoldFrames, forKey: .lostFaceHoldFrames)
        try container.encode(confidenceThreshold, forKey: .confidenceThreshold)
        try container.encode(portraitModeEnabled, forKey: .portraitModeEnabled)
        try container.encode(portraitBlurStrength, forKey: .portraitBlurStrength)
        try container.encode(virtualBackgroundMode, forKey: .virtualBackgroundMode)
        try container.encode(virtualBackgroundGradient, forKey: .virtualBackgroundGradient)
        try container.encode(customBackgrounds, forKey: .customBackgrounds)
        try container.encodeIfPresent(selectedCustomBackgroundID, forKey: .selectedCustomBackgroundID)
        try container.encode(performancePolicy, forKey: .performancePolicy)
        try container.encode(exposure, forKey: .exposure)
        try container.encode(contrast, forKey: .contrast)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(tint, forKey: .tint)
        try container.encode(vibrance, forKey: .vibrance)
        try container.encode(saturation, forKey: .saturation)
        try container.encode(sharpness, forKey: .sharpness)
        try container.encode(showInMenuBar, forKey: .showInMenuBar)
        try container.encode(showDockIcon, forKey: .showDockIcon)
        try container.encode(keepRunningOnClose, forKey: .keepRunningOnClose)
    }

    public static let `default` = AutoFrameSettings()

    public var selectedCustomBackgroundPath: String? {
        guard let id = selectedCustomBackgroundID,
              let bg = customBackgrounds.first(where: { $0.id == id }) else { return nil }
        let container = SharedStorage.containerDirectory()
        return container.appendingPathComponent(bg.fileName).path
    }
}

public struct CameraDeviceDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String { uniqueID }
    public let uniqueID: String
    public let localizedName: String
    public let isBuiltIn: Bool
    public let maxResolution: CGSize?
    public let maxFrameRate: Double?

    public var label: String {
        var parts = [localizedName]
        if let maxResolution {
            parts.append("\(Int(maxResolution.width))x\(Int(maxResolution.height))")
        }
        if let maxFrameRate {
            parts.append(String(format: "%.0f fps", maxFrameRate))
        }
        return parts.joined(separator: " • ")
    }
}

public struct DetectedFace: Equatable, Sendable {
    public let rect: CGRect
    public let confidence: Float

    public init(rect: CGRect, confidence: Float) {
        self.rect = rect
        self.confidence = confidence
    }
}

public struct FrameStatistics: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var captureFPS: Double
    public var processingFPS: Double
    public var relayFPS: Double
    public var targetFPS: Double
    public var faceConfidence: Float
    public var cropCoverage: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var outputWidth: Int
    public var outputHeight: Int
    public var adaptiveQualityActive: Bool
    public var detectionStride: Int
    public var segmentationStride: Int

    public var inputFPS: Double {
        captureFPS
    }

    public var outputFPS: Double {
        relayFPS > 0 ? relayFPS : processingFPS
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case captureFPS
        case processingFPS
        case relayFPS
        case targetFPS
        case inputFPS
        case outputFPS
        case faceConfidence
        case cropCoverage
        case sourceWidth
        case sourceHeight
        case outputWidth
        case outputHeight
        case adaptiveQualityActive
        case detectionStride
        case segmentationStride
    }

    public init(
        timestamp: Date,
        captureFPS: Double,
        processingFPS: Double,
        relayFPS: Double,
        targetFPS: Double,
        faceConfidence: Float,
        cropCoverage: Double,
        sourceWidth: Int,
        sourceHeight: Int,
        outputWidth: Int,
        outputHeight: Int,
        adaptiveQualityActive: Bool,
        detectionStride: Int,
        segmentationStride: Int
    ) {
        self.timestamp = timestamp
        self.captureFPS = captureFPS
        self.processingFPS = processingFPS
        self.relayFPS = relayFPS
        self.targetFPS = targetFPS
        self.faceConfidence = faceConfidence
        self.cropCoverage = cropCoverage
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.adaptiveQualityActive = adaptiveQualityActive
        self.detectionStride = detectionStride
        self.segmentationStride = segmentationStride
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? .distantPast
        let legacyInputFPS = try container.decodeIfPresent(Double.self, forKey: .inputFPS) ?? 0
        let legacyOutputFPS = try container.decodeIfPresent(Double.self, forKey: .outputFPS) ?? 0
        captureFPS = try container.decodeIfPresent(Double.self, forKey: .captureFPS) ?? legacyInputFPS
        processingFPS = try container.decodeIfPresent(Double.self, forKey: .processingFPS) ?? legacyOutputFPS
        relayFPS = try container.decodeIfPresent(Double.self, forKey: .relayFPS) ?? 0
        targetFPS = try container.decodeIfPresent(Double.self, forKey: .targetFPS) ?? 0
        faceConfidence = try container.decodeIfPresent(Float.self, forKey: .faceConfidence) ?? 0
        cropCoverage = try container.decodeIfPresent(Double.self, forKey: .cropCoverage) ?? 1
        sourceWidth = try container.decodeIfPresent(Int.self, forKey: .sourceWidth) ?? 0
        sourceHeight = try container.decodeIfPresent(Int.self, forKey: .sourceHeight) ?? 0
        outputWidth = try container.decodeIfPresent(Int.self, forKey: .outputWidth) ?? 0
        outputHeight = try container.decodeIfPresent(Int.self, forKey: .outputHeight) ?? 0
        adaptiveQualityActive = try container.decodeIfPresent(Bool.self, forKey: .adaptiveQualityActive) ?? false
        detectionStride = try container.decodeIfPresent(Int.self, forKey: .detectionStride) ?? 0
        segmentationStride = try container.decodeIfPresent(Int.self, forKey: .segmentationStride) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(captureFPS, forKey: .captureFPS)
        try container.encode(processingFPS, forKey: .processingFPS)
        try container.encode(relayFPS, forKey: .relayFPS)
        try container.encode(targetFPS, forKey: .targetFPS)
        try container.encode(faceConfidence, forKey: .faceConfidence)
        try container.encode(cropCoverage, forKey: .cropCoverage)
        try container.encode(sourceWidth, forKey: .sourceWidth)
        try container.encode(sourceHeight, forKey: .sourceHeight)
        try container.encode(outputWidth, forKey: .outputWidth)
        try container.encode(outputHeight, forKey: .outputHeight)
        try container.encode(adaptiveQualityActive, forKey: .adaptiveQualityActive)
        try container.encode(detectionStride, forKey: .detectionStride)
        try container.encode(segmentationStride, forKey: .segmentationStride)
    }

    public static let empty = FrameStatistics(
        timestamp: .distantPast,
        captureFPS: 0,
        processingFPS: 0,
        relayFPS: 0,
        targetFPS: 0,
        faceConfidence: 0,
        cropCoverage: 1,
        sourceWidth: 0,
        sourceHeight: 0,
        outputWidth: 0,
        outputHeight: 0,
        adaptiveQualityActive: false,
        detectionStride: 0,
        segmentationStride: 0
    )
}

public struct ProcessedFrame {
    public let pixelBuffer: CVPixelBuffer
    public let cropRect: CGRect
    public let detectedFace: DetectedFace?
    public let statistics: FrameStatistics
}
