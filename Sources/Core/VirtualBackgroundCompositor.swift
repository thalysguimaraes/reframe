import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Composites a sharp foreground person over a virtual background using
/// Vision person segmentation and Core Image filters.
///
/// Designed to run on the already-reframed output buffer (720p/1080p) so
/// segmentation cost stays bounded regardless of raw camera resolution.
public final class VirtualBackgroundCompositor {

    // MARK: - Configuration

    /// Tighter erode than portrait blur — virtual backgrounds reveal mask edges more.
    private static let maskErodeRadius: Double = 1.5

    /// Feather for smooth edge transition.
    private static let maskFeatherRadius: Double = 1.2

    /// Gamma to sharpen the mask transition toward fully-opaque in the person region.
    private static let maskGamma: Double = 0.5

    // MARK: - State

    private let ciContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    private let segmentationRequest = VNGeneratePersonSegmentationRequest()
    private var lastMask: CIImage?
    private var framesSinceSegmentation = 0
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    private var cachedBackground: CIImage?
    private var cachedBackgroundKey: String?

    // MARK: - Public

    public init() {
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    public func reset() {
        lastMask = nil
        framesSinceSegmentation = 0
    }

    /// Applies virtual background replacement to `pixelBuffer`.
    ///
    /// - Returns: A new pixel buffer with the person composited over the virtual background,
    ///   or `nil` if compositing fails (caller should use the original buffer).
    public func apply(
        to pixelBuffer: CVPixelBuffer,
        settings: AutoFrameSettings,
        profile: AdaptiveProcessingProfile
    ) -> CVPixelBuffer? {
        guard settings.virtualBackgroundMode != .off else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let outputSize = CGSize(width: width, height: height)

        guard let background = resolveBackground(settings: settings, outputSize: outputSize) else {
            return nil
        }

        framesSinceSegmentation += 1

        let needsSegmentation = framesSinceSegmentation >= profile.segmentationStride || lastMask == nil
        if needsSegmentation {
            framesSinceSegmentation = 0
            if let newMask = generatePersonMask(from: pixelBuffer, quality: profile.segmentationQuality) {
                lastMask = newMask
            }
        }

        guard let mask = lastMask else {
            return nil
        }

        return composite(pixelBuffer: pixelBuffer, mask: mask, background: background)
    }

    // MARK: - Background Resolution

    private func resolveBackground(settings: AutoFrameSettings, outputSize: CGSize) -> CIImage? {
        let key: String
        switch settings.virtualBackgroundMode {
        case .off:
            return nil
        case .gradient:
            key = "gradient:\(settings.virtualBackgroundGradient.rawValue):\(Int(outputSize.width))x\(Int(outputSize.height))"
        case .customImage:
            key = "image:\(settings.selectedCustomBackgroundPath ?? ""):\(Int(outputSize.width))x\(Int(outputSize.height))"
        }

        if key == cachedBackgroundKey, let cached = cachedBackground {
            return cached
        }

        let bg: CIImage?
        switch settings.virtualBackgroundMode {
        case .off:
            return nil
        case .gradient:
            bg = generateGradient(preset: settings.virtualBackgroundGradient, size: outputSize)
        case .customImage:
            bg = loadCustomImage(path: settings.selectedCustomBackgroundPath, size: outputSize)
        }

        cachedBackground = bg
        cachedBackgroundKey = key
        return bg
    }

    private func generateGradient(preset: GradientPreset, size: CGSize) -> CIImage? {
        let (color0, color1): (CIColor, CIColor)
        switch preset {
        case .warmSunset:
            color0 = CIColor(red: 0.95, green: 0.45, blue: 0.25)
            color1 = CIColor(red: 0.45, green: 0.20, blue: 0.55)
        case .coolOcean:
            color0 = CIColor(red: 0.10, green: 0.55, blue: 0.70)
            color1 = CIColor(red: 0.15, green: 0.20, blue: 0.45)
        case .softLavender:
            color0 = CIColor(red: 0.85, green: 0.80, blue: 0.95)
            color1 = CIColor(red: 0.95, green: 0.92, blue: 0.98)
        }

        let rect = CGRect(origin: .zero, size: size)
        guard let gradient = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: size.width * 0.5, y: 0),
            "inputPoint1": CIVector(x: size.width * 0.5, y: size.height),
            "inputColor0": color0,
            "inputColor1": color1,
        ])?.outputImage?.cropped(to: rect) else {
            return nil
        }
        return gradient
    }

    private func loadCustomImage(path: String?, size: CGSize) -> CIImage? {
        guard let path, !path.isEmpty,
              let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        let imageExtent = image.extent
        let targetRect = CGRect(origin: .zero, size: size)

        // Scale to fill (cover), then center-crop.
        let scaleX = size.width / imageExtent.width
        let scaleY = size.height / imageExtent.height
        let scale = max(scaleX, scaleY)

        let scaledWidth = imageExtent.width * scale
        let scaledHeight = imageExtent.height * scale
        let offsetX = (scaledWidth - size.width) / 2
        let offsetY = (scaledHeight - size.height) / 2

        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))
            .cropped(to: targetRect)

        return scaled
    }

    // MARK: - Segmentation

    private func generatePersonMask(from pixelBuffer: CVPixelBuffer, quality: SegmentationQuality) -> CIImage? {
        segmentationRequest.qualityLevel = quality.visionQualityLevel
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([segmentationRequest])
        } catch {
            NSLog("[AutoFrame] Virtual background segmentation failed: %@", "\(error)")
            return nil
        }

        guard let result = segmentationRequest.results?.first else {
            return nil
        }
        return CIImage(cvPixelBuffer: result.pixelBuffer)
    }

    // MARK: - Compositing

    private func composite(pixelBuffer: CVPixelBuffer, mask: CIImage, background: CIImage) -> CVPixelBuffer? {
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = sourceImage.extent

        // Scale mask to match source image dimensions.
        let maskExtent = mask.extent
        let scaledMask: CIImage
        if maskExtent.size != imageSize.size {
            let sx = imageSize.width / maskExtent.width
            let sy = imageSize.height / maskExtent.height
            scaledMask = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        } else {
            scaledMask = mask
        }

        // 1. Erode: shrink mask boundary inward to avoid halo.
        let erodedMask = scaledMask
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: Self.maskErodeRadius])
            .cropped(to: imageSize)

        // 2. Feather: smooth edge transition.
        let featheredMask = erodedMask
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Self.maskFeatherRadius)
            .cropped(to: imageSize)

        // 3. Gamma sharpen: push greys toward white for crisp foreground.
        let sharpenedMask = featheredMask.applyingFilter("CIGammaAdjust", parameters: [
            "inputPower": Self.maskGamma,
        ])

        // Composite: sharp foreground (where mask is white) over virtual background.
        let composited = sourceImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: sharpenedMask,
        ])

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let output = makePixelBuffer(size: CGSize(width: width, height: height)) else {
            return nil
        }

        ciContext.render(composited, to: output)
        return output
    }

    private func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            poolSize = size
            pool = createPool(size: size)
        }

        guard let pool else { return nil }

        var outputBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer) == kCVReturnSuccess else {
            return nil
        }
        return outputBuffer
    }

    private func createPool(size: CGSize) -> CVPixelBufferPool? {
        let attributes: [NSString: Any] = [
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey: [
                "IOSurfaceIsGlobal" as CFString: true,
            ],
        ]

        var bufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &bufferPool)
        return bufferPool
    }
}

private extension SegmentationQuality {
    var visionQualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel {
        switch self {
        case .accurate:
            return .accurate
        case .balanced:
            return .balanced
        case .fast:
            return .fast
        }
    }
}
