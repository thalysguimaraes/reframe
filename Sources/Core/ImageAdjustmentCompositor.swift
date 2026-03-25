import CoreImage
import CoreVideo

/// Applies exposure, contrast, white balance, vibrance, saturation, and sharpness
/// adjustments using a Core Image filter chain. Returns nil (passthrough) when all
/// values are at their neutral defaults.
public final class ImageAdjustmentCompositor {

    private let ciContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    public init() {}

    public func reset() {
        pool = nil
        poolSize = .zero
    }

    /// Returns an adjusted pixel buffer, or nil if all settings are neutral.
    public func apply(to pixelBuffer: CVPixelBuffer, settings: AutoFrameSettings) -> CVPixelBuffer? {
        guard needsProcessing(settings) else { return nil }

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent

        // 1. Exposure
        if abs(settings.exposure) > 0.001 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: settings.exposure,
            ])
        }

        // 2. Contrast + Saturation
        if abs(settings.contrast - 1.0) > 0.001 || abs(settings.saturation - 1.0) > 0.001 {
            image = image.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: settings.contrast,
                kCIInputSaturationKey: settings.saturation,
            ])
        }

        // 3. White Balance (temperature + tint)
        if abs(settings.temperature - 6500.0) > 1.0 || abs(settings.tint) > 0.1 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: CGFloat(settings.temperature), y: CGFloat(settings.tint)),
                "inputTargetNeutral": CIVector(x: 6500, y: 0),
            ])
        }

        // 4. Vibrance
        if abs(settings.vibrance) > 0.001 {
            image = image.applyingFilter("CIVibrance", parameters: [
                "inputAmount": settings.vibrance,
            ])
        }

        // 5. Sharpness
        if settings.sharpness > 0.001 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: settings.sharpness,
            ])
        }

        // Crop to original extent (some filters expand)
        image = image.cropped(to: extent)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let output = makePixelBuffer(size: CGSize(width: width, height: height)) else {
            return nil
        }

        ciContext.render(image, to: output)
        return output
    }

    private func needsProcessing(_ s: AutoFrameSettings) -> Bool {
        abs(s.exposure) > 0.001
            || abs(s.contrast - 1.0) > 0.001
            || abs(s.saturation - 1.0) > 0.001
            || abs(s.temperature - 6500.0) > 1.0
            || abs(s.tint) > 0.1
            || abs(s.vibrance) > 0.001
            || s.sharpness > 0.001
    }

    private func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            poolSize = size
            pool = createPool(size: size)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess else {
            return nil
        }
        return buffer
    }

    private func createPool(size: CGSize) -> CVPixelBufferPool? {
        let attrs: [NSString: Any] = [
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey: ["IOSurfaceIsGlobal" as CFString: true],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        return pool
    }
}
