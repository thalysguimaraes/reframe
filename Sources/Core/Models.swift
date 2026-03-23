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

    public var frameDuration: CMTime {
        CMTime(value: 1, timescale: 30)
    }

    public var aspectRatio: CGFloat {
        size.width / size.height
    }

    public var displayName: String {
        rawValue
    }
}

public struct AutoFrameSettings: Codable, Equatable, Sendable {
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

    public init(
        cameraID: String? = nil,
        outputResolution: OutputResolution = .hd1080,
        framingPreset: FramingPreset = .medium,
        smoothing: Double = 0.82,
        zoomStrength: Double = 0.5,
        deadZone: Double = 0.08,
        trackingEnabled: Bool = true,
        detectionStride: Int = 2,
        lostFaceHoldFrames: Int = 24,
        confidenceThreshold: Float = 0.4
    ) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case cameraID
        case outputResolution
        case framingPreset
        case smoothing
        case zoomStrength
        case deadZone
        case trackingEnabled
        case detectionStride
        case lostFaceHoldFrames
        case confidenceThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
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
    }

    public static let `default` = AutoFrameSettings()
}

public struct CameraDeviceDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String { uniqueID }
    public let uniqueID: String
    public let localizedName: String
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
    public let timestamp: Date
    public let inputFPS: Double
    public let outputFPS: Double
    public let faceConfidence: Float
    public let cropCoverage: Double
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let outputWidth: Int
    public let outputHeight: Int

    public static let empty = FrameStatistics(
        timestamp: .distantPast,
        inputFPS: 0,
        outputFPS: 0,
        faceConfidence: 0,
        cropCoverage: 1,
        sourceWidth: 0,
        sourceHeight: 0,
        outputWidth: 0,
        outputHeight: 0
    )
}

public struct ProcessedFrame {
    public let pixelBuffer: CVPixelBuffer
    public let cropRect: CGRect
    public let detectedFace: DetectedFace?
    public let statistics: FrameStatistics
}
