import AutoFrameCore
@preconcurrency import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var cameras: [CameraDeviceDescriptor] = []
    @Published var selectedCameraID: String?
    @Published var selectedOutput: OutputResolution
    @Published var selectedPreset: FramingPreset
    @Published var smoothing: Double
    @Published var zoomStrength: Double
    @Published var trackingEnabled: Bool
    @Published var portraitModeEnabled: Bool
    @Published var portraitBlurStrength: Double
    @Published var hasPreviewFrame = false
    @Published var previewFPS = 0.0
    @Published var stats: FrameStatistics
    @Published var statusMessage = "Ready."

    let extensionManager = SystemExtensionManager()
    let previewStream = PreviewStream()

    private let settingsStore = SharedSettingsStore.shared
    private let statsStore = SharedStatsStore.shared
    private let videoFrameStore = SharedVideoFrameStore.shared
    private let deadZone: Double
    private let performancePolicy: PerformancePolicy
    private var pipeline: AutoFramePipeline?
    private var statsRefreshTimer: Timer?
    private var lastStatsUIUpdateTime: CFAbsoluteTime = .zero
    private var lastFacePresence: Bool?

    init() {
        let settings = settingsStore.load()
        self.selectedCameraID = settings.cameraID
        self.selectedOutput = settings.outputResolution
        self.selectedPreset = settings.framingPreset
        self.smoothing = settings.smoothing
        self.zoomStrength = settings.zoomStrength
        self.trackingEnabled = settings.trackingEnabled
        self.portraitModeEnabled = settings.portraitModeEnabled
        self.portraitBlurStrength = settings.portraitBlurStrength
        self.stats = statsStore.load() ?? .empty
        self.deadZone = settings.deadZone
        self.performancePolicy = settings.performancePolicy
        refreshCameras()

        previewStream.onFrameEnqueued = { [weak self] fps in
            Task { @MainActor in
                self?.previewFPS = fps
                self?.hasPreviewFrame = true
            }
        }
    }

    var currentSettings: AutoFrameSettings {
        AutoFrameSettings(
            cameraID: selectedCameraID,
            outputResolution: selectedOutput,
            framingPreset: selectedPreset,
            smoothing: smoothing,
            zoomStrength: zoomStrength,
            deadZone: deadZone,
            trackingEnabled: trackingEnabled,
            portraitModeEnabled: portraitModeEnabled,
            portraitBlurStrength: portraitBlurStrength,
            performancePolicy: performancePolicy
        )
    }

    var portraitBlurLabel: String {
        switch portraitBlurStrength {
        case ..<0.34:
            return "Subtle"
        case ..<0.67:
            return "Medium"
        default:
            return "Strong"
        }
    }

    var zoomLabel: String {
        switch zoomStrength {
        case ..<0.34:
            return "Wide"
        case ..<0.67:
            return "Balanced"
        default:
            return "Close"
        }
    }

    func onAppear() {
        extensionManager.refreshStatus()
        persistSettings()
        startStatsRefreshTimer()
        requestCameraAccessAndStartPreview()
    }

    func installExtension() {
        extensionManager.activateExtension()
    }

    func uninstallExtension() {
        extensionManager.deactivateExtension()
    }

    func refreshCameras() {
        cameras = CameraCatalog.videoDevices()
        if selectedCameraID == nil {
            selectedCameraID = cameras.first?.uniqueID
        }
    }

    func startPreview() {
        stopPreview()
        refreshCameras()
        hasPreviewFrame = false
        previewFPS = 0
        lastStatsUIUpdateTime = .zero
        lastFacePresence = nil

        guard selectedCameraID != nil else {
            videoFrameStore.clear()
            statusMessage = "No camera available."
            return
        }

        let pipeline = AutoFramePipeline(
            settingsProvider: { [weak self] in
                self?.currentSettings ?? .default
            },
            statsStore: statsStore
        )
        let videoFrameStore = self.videoFrameStore
        let previewStream = self.previewStream

        pipeline.onProcessedFrame = { [weak self] frame in
            videoFrameStore.publish(frame.pixelBuffer)
            previewStream.enqueue(frame.pixelBuffer)

            Task { @MainActor in
                guard let self else { return }
                self.publishFrameStatistics(frame.statistics, hasFace: frame.detectedFace != nil)
            }
        }

        do {
            try pipeline.start(cameraID: selectedCameraID)
            self.pipeline = pipeline
            statusMessage = "Preview started."
        } catch {
            statusMessage = "Preview failed: \(error)"
            NSLog("[AutoFrame] Preview failed: %@", "\(error)")
        }
    }

    func stopPreview() {
        pipeline?.stop()
        pipeline = nil
        previewStream.reset()
        videoFrameStore.clear()
        hasPreviewFrame = false
        previewFPS = 0
        statusMessage = "Preview stopped."
    }

    func persistSettings() {
        do {
            try settingsStore.save(currentSettings)
        } catch {
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    func applySettings() {
        persistSettings()
        startPreview()
    }

    private func requestCameraAccessAndStartPreview() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startPreview()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        self.startPreview()
                    } else {
                        self.statusMessage = "Camera access denied."
                    }
                }
            }
        default:
            statusMessage = "Camera access denied."
        }
    }

    private func startStatsRefreshTimer() {
        guard statsRefreshTimer == nil else { return }

        statsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let sharedStats = self.statsStore.load() else { return }
            Task { @MainActor in
                self.stats.relayFPS = sharedStats.relayFPS
                self.stats.outputWidth = sharedStats.outputWidth
                self.stats.outputHeight = sharedStats.outputHeight
            }
        }
    }

    private func publishFrameStatistics(_ frameStatistics: FrameStatistics, hasFace: Bool) {
        let now = CFAbsoluteTimeGetCurrent()
        let faceStateChanged = lastFacePresence != hasFace

        guard faceStateChanged || now - lastStatsUIUpdateTime >= 0.1 else {
            return
        }

        lastStatsUIUpdateTime = now
        lastFacePresence = hasFace

        var mergedStats = frameStatistics
        mergedStats.relayFPS = stats.relayFPS
        stats = mergedStats
        statusMessage = hasFace ? "Preview running — tracking face" : "Preview running — no face found"
    }
}
