import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Composites a sharp foreground person over a blurred background using
/// Vision person segmentation and Core Image filters.
///
/// Designed to run on the already-reframed output buffer (720p/1080p) so
/// segmentation cost stays bounded regardless of raw camera resolution.
public final class PortraitCompositor {

    // MARK: - Configuration

    /// Maps the 0…1 user-facing blur strength to a CIGaussianBlur radius range.
    private static let minBlurRadius: Double = 8
    private static let maxBlurRadius: Double = 40

    /// Erode the mask inward before feathering so the soft transition sits
    /// on the real silhouette boundary instead of bleeding outward (halo).
    /// Keep small to avoid clipping thin accessories like headphones.
    private static let maskErodeRadius: Double = 1.0

    /// How many pixels to feather/smooth the person mask edge after erosion.
    private static let maskFeatherRadius: Double = 1.5

    /// Gamma applied to the mask to tighten the soft edge toward fully-opaque
    /// inside the person region. Values < 1 push grey toward white (sharper).
    private static let maskGamma: Double = 0.6

    // MARK: - State

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastMask: CIImage?
    private var framesSinceSegmentation = 0

    /// Run segmentation every N frames to save GPU/ANE budget.
    /// Reuse the previous mask on skipped frames.
    private let segmentationStride = 2

    // MARK: - Public

    public init() {}

    /// Resets cached mask state. Call when the pipeline restarts or settings change
    /// in a way that invalidates the mask (e.g. camera switch).
    public func reset() {
        lastMask = nil
        framesSinceSegmentation = 0
    }

    /// Applies portrait background blur to `pixelBuffer`.
    ///
    /// - Parameters:
    ///   - pixelBuffer: The reframed output buffer (720p or 1080p, BGRA).
    ///   - blurStrength: User-facing 0…1 value controlling blur intensity.
    /// - Returns: A new pixel buffer with the person sharp and background blurred,
    ///   or `nil` if compositing fails (caller should use the original buffer).
    public func apply(to pixelBuffer: CVPixelBuffer, blurStrength: Double) -> CVPixelBuffer? {
        framesSinceSegmentation += 1

        let needsSegmentation = framesSinceSegmentation >= segmentationStride || lastMask == nil
        if needsSegmentation {
            framesSinceSegmentation = 0
            if let newMask = generatePersonMask(from: pixelBuffer) {
                lastMask = newMask
            }
            // If segmentation fails, keep using lastMask (which may be nil on first frame).
        }

        guard let mask = lastMask else {
            // No mask available yet — return nil so the caller uses the unblurred frame.
            return nil
        }

        return composite(pixelBuffer: pixelBuffer, mask: mask, blurStrength: blurStrength)
    }

    // MARK: - Segmentation

    private func generatePersonMask(from pixelBuffer: CVPixelBuffer) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("[AutoFrame] Person segmentation failed: %@", "\(error)")
            return nil
        }

        guard let result = request.results?.first else {
            return nil
        }
        let maskBuffer = result.pixelBuffer

        return CIImage(cvPixelBuffer: maskBuffer)
    }

    // MARK: - Compositing

    private func composite(pixelBuffer: CVPixelBuffer, mask: CIImage, blurStrength: Double) -> CVPixelBuffer? {
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

        // 1. Erode: pull the mask boundary inward so the feathered transition
        //    doesn't extend outward into the background (eliminates the halo).
        //    CIMorphologyMinimum shrinks bright (person) regions by `radius` pixels.
        let erodedMask = scaledMask
            .clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: Self.maskErodeRadius])
            .cropped(to: imageSize)

        // 2. Feather: gentle blur for a smooth, natural edge after erosion.
        let featheredMask = erodedMask
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Self.maskFeatherRadius)
            .cropped(to: imageSize)

        // 3. Sharpen the transition curve: apply gamma < 1 so greys near the
        //    person edge push toward white, keeping the foreground crisp while
        //    the background-side fade stays soft.
        let sharpenedMask = featheredMask.applyingFilter("CIGammaAdjust", parameters: [
            "inputPower": Self.maskGamma,
        ])

        // Blur the full image for the background.
        let blurRadius = Self.minBlurRadius + (Self.maxBlurRadius - Self.minBlurRadius) * blurStrength
        let blurredBackground = sourceImage
            .clampedToExtent()
            .applyingGaussianBlur(sigma: blurRadius)
            .cropped(to: imageSize)

        // Composite: sharp foreground (where mask is white) over blurred background.
        let composited = sourceImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurredBackground,
            kCIInputMaskImageKey: sharpenedMask,
        ])

        // Render to a new pixel buffer.
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var outputBuffer: CVPixelBuffer?
        let attrs: [NSString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                   kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                                   &outputBuffer) == kCVReturnSuccess,
              let output = outputBuffer else {
            return nil
        }

        ciContext.render(composited, to: output)
        return output
    }
}
