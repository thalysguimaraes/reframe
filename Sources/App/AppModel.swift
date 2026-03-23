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
    @Published var previewImage: CGImage?
    @Published var stats: FrameStatistics
    @Published var statusMessage = "Ready."

    let extensionManager = SystemExtensionManager()

    private let settingsStore = SharedSettingsStore.shared
    private let statsStore = SharedStatsStore.shared
    private let deadZone: Double
    private var pipeline: AutoFramePipeline?

    init() {
        let settings = settingsStore.load()
        self.selectedCameraID = settings.cameraID
        self.selectedOutput = settings.outputResolution
        self.selectedPreset = settings.framingPreset
        self.smoothing = settings.smoothing
        self.zoomStrength = settings.zoomStrength
        self.trackingEnabled = settings.trackingEnabled
        self.stats = statsStore.load() ?? .empty
        self.deadZone = settings.deadZone
        refreshCameras()
    }

    var currentSettings: AutoFrameSettings {
        AutoFrameSettings(
            cameraID: selectedCameraID,
            outputResolution: selectedOutput,
            framingPreset: selectedPreset,
            smoothing: smoothing,
            zoomStrength: zoomStrength,
            deadZone: deadZone,
            trackingEnabled: trackingEnabled
        )
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
        persistSettings()
        requestCameraAccessAndStartPreview()
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

        guard selectedCameraID != nil else {
            statusMessage = "No camera available."
            return
        }

        let pipeline = AutoFramePipeline(
            settingsProvider: { [weak self] in
                self?.currentSettings ?? .default
            },
            statsStore: statsStore
        )

        pipeline.onProcessedFrame = { [weak self] frame in
            guard let self else { return }
            let cgImage = PreviewImageFactory.makeCGImage(from: frame.pixelBuffer)

            Task { @MainActor in
                self.previewImage = cgImage
                self.stats = frame.statistics
                self.statusMessage = frame.detectedFace == nil ? "Preview running — no face found" : "Preview running — tracking face"
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
    }

    func installExtension() {
        extensionManager.activateExtension()
    }

    func uninstallExtension() {
        extensionManager.deactivateExtension()
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
}
