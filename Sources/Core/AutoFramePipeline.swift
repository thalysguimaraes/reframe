@preconcurrency import AVFoundation
import CoreGraphics
@preconcurrency import CoreMedia
import Foundation

public final class AutoFramePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public var onProcessedFrame: ((ProcessedFrame) -> Void)?

    private let settingsProvider: () -> AutoFrameSettings
    private let statsStore: SharedStatsStore?
    private let adaptiveQualityController = AdaptiveQualityController()
    private let faceDetector = FaceDetector()
    private let faceStabilizer = FaceObservationStabilizer()
    private let cropEngine = CropEngine()
    private let reframer = PixelBufferReframer()
    private let portraitCompositor = PortraitCompositor()
    private let captureQueue = DispatchQueue(label: "dev.autoframe.pipeline.capture", qos: .userInitiated)
    private let captureStateQueue = DispatchQueue(label: "dev.autoframe.pipeline.capture-state", qos: .userInitiated)
    private let processingQueue = DispatchQueue(label: "dev.autoframe.pipeline.processing", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "dev.autoframe.pipeline.session", qos: .userInitiated)

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var currentCameraID: String?
    private var activeCaptureDevice: AVCaptureDevice?
    private var pendingSampleBuffer: CMSampleBuffer?
    private var isProcessingFrame = false
    private var frameIndex = 0
    private var lastDetectedFace: DetectedFace?
    private var consecutiveDetectionMisses = 0
    private var sourceUsesHardwareCenterStage = false
    private var currentTargetFrameRate = OutputResolution.hd1080.preferredFrameRate
    private var currentProcessingProfile = AdaptiveProcessingProfile.default
    private var captureFPSWindow: [CFAbsoluteTime] = []
    private var processingFPSWindow: [CFAbsoluteTime] = []
    private var isReconfiguringCaptureFormat = false
    private var hasAppliedCaptureFallback = false

    public init(
        settingsProvider: @escaping () -> AutoFrameSettings,
        statsStore: SharedStatsStore? = nil
    ) {
        self.settingsProvider = settingsProvider
        self.statsStore = statsStore
        super.init()
    }

    public func start(cameraID: String? = nil) throws {
        let activeCameraID = cameraID ?? settingsProvider().cameraID
        try sessionQueue.sync {
            if session.isRunning, currentCameraID == activeCameraID {
                return
            }

            let settings = settingsProvider()
            stopLocked()
            let device = try configureSession(cameraID: activeCameraID, settings: settings)
            cropEngine.reset()
            faceStabilizer.reset()
            consecutiveDetectionMisses = 0
            do {
                session.startRunning()
                try applyCaptureFormat(to: device, settings: settings)
            } catch {
                if session.isRunning {
                    session.stopRunning()
                }
                throw error
            }
            currentCameraID = activeCameraID
        }
    }

    public func stop() {
        sessionQueue.sync {
            stopLocked()
        }
    }

    private func stopLocked() {
        if session.isRunning {
            session.stopRunning()
        }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        captureStateQueue.sync {
            pendingSampleBuffer = nil
            isProcessingFrame = false
            captureFPSWindow.removeAll(keepingCapacity: true)
        }

        processingQueue.sync {
            cropEngine.reset()
            faceStabilizer.reset()
            portraitCompositor.reset()
            adaptiveQualityController.reset()
            frameIndex = 0
            lastDetectedFace = nil
            consecutiveDetectionMisses = 0
            sourceUsesHardwareCenterStage = false
            currentTargetFrameRate = OutputResolution.hd1080.preferredFrameRate
            currentProcessingProfile = .default
            processingFPSWindow.removeAll(keepingCapacity: true)
            isReconfiguringCaptureFormat = false
            hasAppliedCaptureFallback = false
        }

        currentCameraID = nil
        activeCaptureDevice = nil
    }

    private func configureSession(cameraID: String?, settings: AutoFrameSettings) throws -> AVCaptureDevice {
        guard let device = CameraCatalog.device(for: cameraID) else {
            throw AutoFramePipelineError.cameraUnavailable
        }

        session.beginConfiguration()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AutoFramePipelineError.couldNotAddInput
        }
        session.addInput(input)

        configureCenterStageBehavior(for: device, settings: settings)
        session.sessionPreset = supportedSessionPreset(for: session, outputResolution: settings.outputResolution)
        processingQueue.sync {
            currentTargetFrameRate = settings.outputResolution.fallbackFrameRate
        }
        activeCaptureDevice = device

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw AutoFramePipelineError.couldNotAddOutput
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()
        return device
    }

    private func configureCenterStageBehavior(for device: AVCaptureDevice, settings: AutoFrameSettings) {
        guard #available(macOS 12.3, *) else {
            processingQueue.sync {
                sourceUsesHardwareCenterStage = false
            }
            return
        }

        let supportsHardwareCenterStage = device.formats.contains { $0.isCenterStageSupported }
        processingQueue.sync {
            sourceUsesHardwareCenterStage = supportsHardwareCenterStage && device.isCenterStageActive
        }

        // If the source camera already has Apple framing active, don't fight it with software recentering.
        if supportsHardwareCenterStage && settings.trackingEnabled {
            NSLog(
                "[AutoFrame] Source camera supports Center Stage. active=%@ enabled=%@",
                device.isCenterStageActive.description,
                AVCaptureDevice.isCenterStageEnabled.description
            )
        }
    }

    private func applyCaptureFormat(
        to device: AVCaptureDevice,
        settings: AutoFrameSettings,
        preferredFrameRate: Double? = nil
    ) throws {
        let descriptors = device.formats.enumerated().map { index, format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFrameRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return CaptureFormatDescriptor(dimensions: dimensions, maxFrameRate: maxFrameRate, position: index)
        }

        guard let selection = CaptureFormatSelector.selectBestFormat(
            from: descriptors,
            for: settings,
            preferredFrameRate: preferredFrameRate
        ) else {
            processingQueue.sync {
                currentTargetFrameRate = settings.outputResolution.fallbackFrameRate
            }
            return
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        let selectedFormat = device.formats[selection.descriptor.position]
        guard let frameTiming = selectFrameTiming(
            from: selectedFormat.videoSupportedFrameRateRanges,
            preferredFrameRate: selection.targetFrameRate,
            fallbackFrameRate: settings.outputResolution.fallbackFrameRate
        ) else {
            processingQueue.sync {
                currentTargetFrameRate = settings.outputResolution.fallbackFrameRate
            }
            return
        }

        device.activeFormat = selectedFormat
        device.activeVideoMinFrameDuration = frameTiming.duration
        device.activeVideoMaxFrameDuration = frameTiming.duration

        processingQueue.sync {
            currentTargetFrameRate = frameTiming.frameRate
            currentProcessingProfile = .default
            adaptiveQualityController.reset()
            processingFPSWindow.removeAll(keepingCapacity: true)
            hasAppliedCaptureFallback = frameTiming.frameRate <= settings.outputResolution.fallbackFrameRate + 0.5
        }
    }

    private func supportedSessionPreset(
        for session: AVCaptureSession,
        outputResolution: OutputResolution
    ) -> AVCaptureSession.Preset {
        if outputResolution == .hd1080, session.canSetSessionPreset(.hd1920x1080) {
            return .hd1920x1080
        }
        if outputResolution == .hd720, session.canSetSessionPreset(.hd1280x720) {
            return .hd1280x720
        }
        return .high
    }

    private func selectFrameTiming(
        from ranges: [AVFrameRateRange],
        preferredFrameRate: Double,
        fallbackFrameRate: Double
    ) -> (frameRate: Double, duration: CMTime)? {
        let sortedRanges = ranges.sorted { lhs, rhs in
            lhs.maxFrameRate > rhs.maxFrameRate
        }

        guard !sortedRanges.isEmpty else {
            return nil
        }

        if let preferredRange = sortedRanges.first(where: { $0.maxFrameRate >= preferredFrameRate - 0.5 }) {
            let frameRate = min(preferredRange.maxFrameRate, preferredFrameRate)
            return (frameRate, exactDuration(for: frameRate, in: preferredRange))
        }

        if let fallbackRange = sortedRanges.first(where: { $0.maxFrameRate >= fallbackFrameRate - 0.5 }) {
            let frameRate = min(fallbackRange.maxFrameRate, fallbackFrameRate)
            return (frameRate, exactDuration(for: frameRate, in: fallbackRange))
        }

        return nil
    }

    private func exactDuration(for frameRate: Double, in range: AVFrameRateRange) -> CMTime {
        if abs(frameRate - range.maxFrameRate) < 0.01 {
            return range.minFrameDuration
        }

        if abs(frameRate - range.minFrameRate) < 0.01 {
            return range.maxFrameDuration
        }

        return CMTimeMakeWithSeconds(1 / max(frameRate, 1), preferredTimescale: 1_000_000)
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        let nextSampleBuffer = captureStateQueue.sync { () -> CMSampleBuffer? in
            update(window: &captureFPSWindow, now: now)

            if isProcessingFrame {
                pendingSampleBuffer = sampleBuffer
                return nil
            }

            isProcessingFrame = true
            return sampleBuffer
        }

        guard let nextSampleBuffer else { return }

        processingQueue.async { [weak self] in
            autoreleasepool {
                self?.process(sampleBuffer: nextSampleBuffer)
            }
        }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        defer { schedulePendingFrameIfNeeded() }
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let processingStart = CFAbsoluteTimeGetCurrent()
        var settings = settingsProvider()
        if sourceUsesHardwareCenterStage {
            settings.trackingEnabled = false
        }
        frameIndex += 1
        let captureFPS = captureStateQueue.sync { rollingFPS(from: captureFPSWindow) }
        let targetFrameRate = currentTargetFrameRate
        requestFallbackCaptureFormatIfNeeded(captureFPS: captureFPS, settings: settings, targetFrameRate: targetFrameRate)
        let processingProfile = adaptiveQualityController.currentProfile(for: settings, targetFrameRate: targetFrameRate)
        currentProcessingProfile = processingProfile

        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(sourceBuffer),
            height: CVPixelBufferGetHeight(sourceBuffer)
        )

        let shouldDetect = settings.trackingEnabled && (frameIndex % max(processingProfile.detectionStride, 1) == 0 || frameIndex == 1)
        let freshDetection = shouldDetect ? detectFaceIfNeeded(in: sourceBuffer, settings: settings) : nil
        let face: DetectedFace?
        if let freshDetection {
            consecutiveDetectionMisses = 0
            let stabilizedFace = faceStabilizer.ingest(freshDetection)
            lastDetectedFace = stabilizedFace
            face = stabilizedFace
        } else if shouldDetect {
            consecutiveDetectionMisses += 1
            if consecutiveDetectionMisses <= 2, let lastDetectedFace {
                face = lastDetectedFace
            } else {
                lastDetectedFace = nil
                faceStabilizer.reset()
                face = nil
            }
        } else {
            face = lastDetectedFace
        }
        let cropRect = cropEngine.nextCrop(sourceSize: sourceSize, detectedFace: face, settings: settings)

        guard let reframedBuffer = reframer.render(
            pixelBuffer: sourceBuffer,
            cropRect: cropRect,
            outputSize: settings.outputResolution.size
        ) else {
            return
        }

        // Portrait mode: apply person segmentation + background blur on the reframed output.
        let outputBuffer: CVPixelBuffer
        if settings.portraitModeEnabled && !processingProfile.disablesPortraitEffects {
            outputBuffer = portraitCompositor.apply(
                to: reframedBuffer,
                blurStrength: settings.portraitBlurStrength,
                profile: processingProfile
            ) ?? reframedBuffer
        } else {
            outputBuffer = reframedBuffer
        }

        let processingEnd = CFAbsoluteTimeGetCurrent()
        adaptiveQualityController.recordProcessingDuration(
            processingEnd - processingStart,
            settings: settings,
            targetFrameRate: targetFrameRate
        )
        update(window: &processingFPSWindow, now: processingEnd)

        let stats = FrameStatistics(
            timestamp: Date(),
            captureFPS: captureFPS,
            processingFPS: rollingFPS(from: processingFPSWindow),
            relayFPS: 0,
            targetFPS: targetFrameRate,
            faceConfidence: face?.confidence ?? 0,
            cropCoverage: Double((cropRect.width * cropRect.height) / (sourceSize.width * sourceSize.height)),
            sourceWidth: Int(sourceSize.width),
            sourceHeight: Int(sourceSize.height),
            outputWidth: Int(settings.outputResolution.size.width),
            outputHeight: Int(settings.outputResolution.size.height),
            adaptiveQualityActive: processingProfile.adaptiveQualityActive,
            detectionStride: processingProfile.detectionStride,
            segmentationStride: processingProfile.segmentationStride
        )

        statsStore?.save(stats)

        onProcessedFrame?(
            ProcessedFrame(
                pixelBuffer: outputBuffer,
                cropRect: cropRect,
                detectedFace: face,
                statistics: stats
            )
        )
    }

    private func schedulePendingFrameIfNeeded() {
        let nextSampleBuffer = captureStateQueue.sync { () -> CMSampleBuffer? in
            if let pendingSampleBuffer {
                self.pendingSampleBuffer = nil
                return pendingSampleBuffer
            }

            isProcessingFrame = false
            return nil
        }

        guard let nextSampleBuffer else { return }

        processingQueue.async { [weak self] in
            autoreleasepool {
                self?.process(sampleBuffer: nextSampleBuffer)
            }
        }
    }

    private func detectFaceIfNeeded(in pixelBuffer: CVPixelBuffer, settings: AutoFrameSettings) -> DetectedFace? {
        guard settings.trackingEnabled else { return nil }
        do {
            return try faceDetector.detectLargestFace(in: pixelBuffer)
        } catch {
            if frameIndex <= 3 {
                NSLog("[AutoFrame] Face detection error: %@", "\(error)")
            }
            return nil
        }
    }

    private func requestFallbackCaptureFormatIfNeeded(
        captureFPS: Double,
        settings: AutoFrameSettings,
        targetFrameRate: Double
    ) {
        let fallbackFrameRate = settings.outputResolution.fallbackFrameRate
        guard targetFrameRate > fallbackFrameRate + 0.5 else { return }
        guard captureFPS > 0 else { return }
        guard !isReconfiguringCaptureFormat, !hasAppliedCaptureFallback else { return }
        guard frameIndex >= Int(max(targetFrameRate, fallbackFrameRate)) else { return }
        guard captureFPS < targetFrameRate * 0.85 else { return }

        isReconfiguringCaptureFormat = true
        let measuredCaptureFPS = captureFPS
        sessionQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.processingQueue.async { [weak self] in
                    self?.isReconfiguringCaptureFormat = false
                }
            }

            guard self.session.isRunning, let device = self.activeCaptureDevice else { return }

            let settings = self.settingsProvider()
            do {
                try self.applyCaptureFormat(
                    to: device,
                    settings: settings,
                    preferredFrameRate: settings.outputResolution.fallbackFrameRate
                )
                NSLog(
                    "[AutoFrame] Falling back capture format to %.2f fps after sustained %.1f fps capture",
                    settings.outputResolution.fallbackFrameRate,
                    measuredCaptureFPS
                )
            } catch {
                NSLog("[AutoFrame] Failed to fall back capture format: %@", "\(error)")
            }
        }
    }

    private func update(window: inout [CFAbsoluteTime], now: CFAbsoluteTime) {
        window.append(now)
        window = window.filter { now - $0 <= 1.0 }
    }

    private func rollingFPS(from timestamps: [CFAbsoluteTime]) -> Double {
        guard timestamps.count > 1, let first = timestamps.first, let last = timestamps.last, last > first else {
            return Double(timestamps.count)
        }
        return Double(timestamps.count - 1) / (last - first)
    }
}

public enum AutoFramePipelineError: Error {
    case cameraUnavailable
    case couldNotAddInput
    case couldNotAddOutput
    case couldNotConfigureDevice
}
