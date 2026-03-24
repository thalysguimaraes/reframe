@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

public final class AutoFramePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public var onProcessedFrame: ((ProcessedFrame) -> Void)?

    private let settingsProvider: () -> AutoFrameSettings
    private let statsStore: SharedStatsStore?
    private let faceDetector = FaceDetector()
    private let faceStabilizer = FaceObservationStabilizer()
    private let cropEngine = CropEngine()
    private let reframer = PixelBufferReframer()
    private let portraitCompositor = PortraitCompositor()
    private let processingQueue = DispatchQueue(label: "dev.autoframe.pipeline.processing", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "dev.autoframe.pipeline.session", qos: .userInitiated)

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    private var currentCameraID: String?
    private var frameIndex = 0
    private var lastDetectedFace: DetectedFace?
    private var consecutiveDetectionMisses = 0
    private var sourceUsesHardwareCenterStage = false
    private var inputFPSWindow: [CFAbsoluteTime] = []
    private var outputFPSWindow: [CFAbsoluteTime] = []

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

            stopLocked()
            try configureSession(cameraID: activeCameraID)
            cropEngine.reset()
            faceStabilizer.reset()
            consecutiveDetectionMisses = 0
            session.startRunning()
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
        cropEngine.reset()
        faceStabilizer.reset()
        portraitCompositor.reset()
        currentCameraID = nil
        frameIndex = 0
        lastDetectedFace = nil
        consecutiveDetectionMisses = 0
        sourceUsesHardwareCenterStage = false
        inputFPSWindow.removeAll(keepingCapacity: true)
        outputFPSWindow.removeAll(keepingCapacity: true)
    }

    private func configureSession(cameraID: String?) throws {
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

        configureCenterStageBehavior(for: device, settings: settingsProvider())
        session.sessionPreset = supportedSessionPreset(for: session)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw AutoFramePipelineError.couldNotAddOutput
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()
    }

    private func configureCenterStageBehavior(for device: AVCaptureDevice, settings: AutoFrameSettings) {
        guard #available(macOS 12.3, *) else {
            sourceUsesHardwareCenterStage = false
            return
        }

        let supportsHardwareCenterStage = device.formats.contains { $0.isCenterStageSupported }
        sourceUsesHardwareCenterStage = supportsHardwareCenterStage && device.isCenterStageActive

        // If the source camera already has Apple framing active, don't fight it with software recentering.
        if supportsHardwareCenterStage && settings.trackingEnabled {
            NSLog(
                "[AutoFrame] Source camera supports Center Stage. active=%@ enabled=%@",
                device.isCenterStageActive.description,
                AVCaptureDevice.isCenterStageEnabled.description
            )
        }
    }

    private func supportedSessionPreset(for session: AVCaptureSession) -> AVCaptureSession.Preset {
        if session.canSetSessionPreset(.hd4K3840x2160) {
            return .hd4K3840x2160
        }
        if session.canSetSessionPreset(.hd1920x1080) {
            return .hd1920x1080
        }
        return .high
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        autoreleasepool {
            process(sampleBuffer: sampleBuffer)
        }
    }

    private func process(sampleBuffer: CMSampleBuffer) {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var settings = settingsProvider()
        if sourceUsesHardwareCenterStage {
            settings.trackingEnabled = false
        }
        frameIndex += 1
        let now = CFAbsoluteTimeGetCurrent()
        update(window: &inputFPSWindow, now: now)

        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(sourceBuffer),
            height: CVPixelBufferGetHeight(sourceBuffer)
        )

        let shouldDetect = settings.trackingEnabled && (frameIndex % max(settings.detectionStride, 1) == 0 || frameIndex == 1)
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
        if settings.portraitModeEnabled {
            outputBuffer = portraitCompositor.apply(
                to: reframedBuffer,
                blurStrength: settings.portraitBlurStrength
            ) ?? reframedBuffer
        } else {
            outputBuffer = reframedBuffer
        }

        update(window: &outputFPSWindow, now: now)

        let stats = FrameStatistics(
            timestamp: Date(),
            inputFPS: rollingFPS(from: inputFPSWindow),
            outputFPS: rollingFPS(from: outputFPSWindow),
            faceConfidence: face?.confidence ?? 0,
            cropCoverage: Double((cropRect.width * cropRect.height) / (sourceSize.width * sourceSize.height)),
            sourceWidth: Int(sourceSize.width),
            sourceHeight: Int(sourceSize.height),
            outputWidth: Int(settings.outputResolution.size.width),
            outputHeight: Int(settings.outputResolution.size.height)
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
}
