import AutoFrameCore
@preconcurrency import AVFoundation
import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var cameras: [CameraDeviceDescriptor] = []
    @Published var hasCompletedOnboarding: Bool
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
    @Published var isSidebarVisible = true
    @Published var showsDetailedStats = false
    @Published var showingSettings = false
    @Published var zoomEnabled = true
    @Published var exposure: Double
    @Published var contrast: Double
    @Published var temperature: Double
    @Published var tint: Double
    @Published var vibrance: Double
    @Published var saturation: Double
    @Published var sharpness: Double
    @Published var isAdjustmentsSidebarVisible = true
    @Published var isDarkMode: Bool
    @Published var showingOnboarding = false
    @Published private(set) var cameraAuthorizationStatus: AVAuthorizationStatus
    @Published private(set) var previewState: PreviewState = .idle
    @Published private(set) var pipelineActivity: PipelineActivity?

    let extensionManager = SystemExtensionManager()
    let previewStream = PreviewStream()

    private let settingsStore = SharedSettingsStore.shared
    private let statsStore = SharedStatsStore.shared
    private let videoFrameStore = SharedVideoFrameStore.shared
    private let liveSettingsSnapshot: LiveSettingsSnapshot
    private let deadZone: Double
    private let performancePolicy: PerformancePolicy
    private var pipeline: AutoFramePipeline?
    private var pipelineOperationTask: Task<Void, Never>?
    private var pipelineOperationID = 0
    private var statsRefreshTimer: Timer?
    private var previewSignalTimer: Timer?
    private var previewSignalMonitor = PreviewSignalMonitor()
    private var lastStatsUIUpdateTime: CFAbsoluteTime = .zero
    private var lastFacePresence: Bool?

    init() {
        let settings = settingsStore.load()
        self.liveSettingsSnapshot = LiveSettingsSnapshot(settings)
        self.hasCompletedOnboarding = settings.hasCompletedOnboarding
        self.selectedCameraID = settings.cameraID
        self.selectedOutput = settings.outputResolution
        self.selectedPreset = settings.framingPreset
        self.smoothing = settings.smoothing
        self.zoomStrength = settings.zoomStrength
        self.trackingEnabled = settings.trackingEnabled
        self.portraitModeEnabled = settings.portraitModeEnabled
        self.portraitBlurStrength = settings.portraitBlurStrength
        self.zoomEnabled = settings.zoomStrength > 0
        self.exposure = settings.exposure
        self.contrast = settings.contrast
        self.temperature = settings.temperature
        self.tint = settings.tint
        self.vibrance = settings.vibrance
        self.saturation = settings.saturation
        self.sharpness = settings.sharpness
        self.isDarkMode = Self.systemPrefersDarkMode
        self.stats = statsStore.load() ?? .empty
        self.deadZone = settings.deadZone
        self.performancePolicy = settings.performancePolicy
        self.cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        refreshCameras()

        previewStream.onFrameEnqueued = { [weak self] fps, frameTime in
            Task { @MainActor in
                guard let self else { return }
                self.previewFPS = fps
                self.recordPreviewFrame(at: frameTime)
            }
        }
    }

    var isPipelineBusy: Bool {
        pipelineActivity != nil
    }

    var previewStatusIndicatorColor: Color {
        switch previewState {
        case .live:
            return .green
        case .noSignal:
            return Theme.signalWarning
        case .idle, .warmingUp:
            return Theme.textTertiary
        }
    }

    var suggestedRecoveryCamera: CameraDeviceDescriptor? {
        cameras.first(where: { $0.uniqueID != selectedCameraID })
    }

    var previewWarmupTitle: String {
        "Waiting for video"
    }

    var previewWarmupSubtitle: String {
        "Reframe is waiting for the first frame from \(selectedCameraStatusName)."
    }

    var previewNoSignalTitle: String {
        guard case let .noSignal(reason) = previewState else {
            return "No video signal"
        }

        switch reason {
        case .startupTimeout:
            return selectedCamera?.isBuiltIn == true ? "Built-in camera unavailable" : "No video signal"
        case .interrupted:
            return "Camera not responding"
        }
    }

    var previewNoSignalSubtitle: String {
        guard case let .noSignal(reason) = previewState else {
            return ""
        }

        let cameraName = selectedCameraStatusName
        switch reason {
        case .startupTimeout:
            if selectedCamera?.isBuiltIn == true {
                return "The built-in camera is not available when the MacBook lid is closed. Reopen the lid or switch to another camera."
            }
            return "\(cameraName) is selected but not delivering video frames. Check the cable, power, or privacy settings, then try another camera."
        case .interrupted:
            if selectedCamera?.isBuiltIn == true {
                return "Video from the built-in camera stopped unexpectedly. If the MacBook lid is closed, reopen it or switch to another camera."
            }
            return "Video from \(cameraName) stopped unexpectedly. Check the connection, then switch cameras or retry the preview."
        }
    }

    var switchCameraButtonTitle: String {
        if let suggestedRecoveryCamera {
            return "Switch to \(suggestedRecoveryCamera.localizedName)"
        }
        return "Retry camera"
    }

    private static var systemPrefersDarkMode: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var currentSettings: AutoFrameSettings {
        AutoFrameSettings(
            hasCompletedOnboarding: hasCompletedOnboarding,
            cameraID: selectedCameraID,
            outputResolution: selectedOutput,
            framingPreset: selectedPreset,
            smoothing: smoothing,
            zoomStrength: zoomStrength,
            deadZone: deadZone,
            trackingEnabled: trackingEnabled,
            portraitModeEnabled: portraitModeEnabled,
            portraitBlurStrength: portraitBlurStrength,
            performancePolicy: performancePolicy,
            exposure: exposure,
            contrast: contrast,
            temperature: temperature,
            tint: tint,
            vibrance: vibrance,
            saturation: saturation,
            sharpness: sharpness
        )
    }

    func resetAdjustments() {
        exposure = 0.0
        contrast = 1.0
        temperature = 6500.0
        tint = 0.0
        vibrance = 0.0
        saturation = 1.0
        sharpness = 0.0
        persistSettings()
    }

    var portraitBlurLabel: String {
        if portraitBlurStrength < 0.01 {
            return "Off"
        }

        switch portraitBlurStrength {
        case ..<0.34:
            return "Subtle"
        case ..<0.67:
            return "Medium"
        default:
            return "Strong"
        }
    }

    var contrastLabel: String {
        let relativePercentage = ContrastControlMapping.relativePercentage(for: contrast)
        if abs(relativePercentage) < 0.5 {
            return "0%"
        }
        return String(format: "%+.0f%%", relativePercentage)
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
        startStatsRefreshTimer()
        startPreviewSignalTimer()

        refreshOnboardingPrerequisites()
        persistSettings()

        if hasCompletedOnboarding {
            showingOnboarding = false
            requestCameraAccessAndStartPreview()
        } else {
            showingOnboarding = true
            if cameraAuthorizationStatus == .authorized {
                startPreviewIfNeeded()
            } else if cameraAuthorizationStatus == .denied || cameraAuthorizationStatus == .restricted {
                statusMessage = "Camera access denied."
            } else {
                statusMessage = "Welcome to Reframe."
            }
        }
    }

    func installExtension() {
        extensionManager.activateExtension()
    }

    func uninstallExtension() {
        extensionManager.deactivateExtension()
    }

    func refreshCameras() {
        cameras = CameraCatalog.videoDevices()
        if let selectedCameraID, !cameras.contains(where: { $0.uniqueID == selectedCameraID }) {
            self.selectedCameraID = cameras.first?.uniqueID
        } else if selectedCameraID == nil {
            selectedCameraID = cameras.first?.uniqueID
        }
    }

    func startPreview() {
        refreshCameras()
        persistSettings()
        hasPreviewFrame = false
        previewFPS = 0
        lastStatsUIUpdateTime = .zero
        lastFacePresence = nil

        let settings = currentSettings
        guard settings.cameraID != nil else {
            clearPreviewSignalMonitoring()
            previewStream.reset()
            videoFrameStore.clear()
            statusMessage = "No camera available."
            return
        }

        runPipelineOperation(activity: .starting, clearsPreview: true) { pipeline in
            try await pipeline.startAsync(cameraID: settings.cameraID, settings: settings)
        }
    }

    func stopPreview() {
        pipelineOperationTask?.cancel()
        pipelineOperationTask = nil
        pipelineActivity = nil

        guard let pipeline else {
            previewStream.reset()
            videoFrameStore.clear()
            clearPreviewSignalMonitoring()
            hasPreviewFrame = false
            previewFPS = 0
            statusMessage = "Preview stopped."
            return
        }

        pipelineOperationTask = Task { [weak self, pipeline] in
            await pipeline.stopAsync()

            await MainActor.run {
                guard let self else { return }
                self.previewStream.reset()
                self.videoFrameStore.clear()
                self.clearPreviewSignalMonitoring()
                self.hasPreviewFrame = false
                self.previewFPS = 0
                self.statusMessage = "Preview stopped."
            }
        }
    }

    func applyCameraSelection() {
        persistSettings()
        let settings = currentSettings
        runPipelineOperation(activity: .switchingCamera, clearsPreview: true) { pipeline in
            try await pipeline.reconfigureAsync(cameraID: settings.cameraID, settings: settings)
        }
    }

    func applyOutputSelection() {
        persistSettings()
        let settings = currentSettings
        runPipelineOperation(activity: .changingResolution(settings.outputResolution), clearsPreview: false) { pipeline in
            try await pipeline.reconfigureAsync(cameraID: settings.cameraID, settings: settings)
        }
    }

    func persistSettings() {
        let settings = currentSettings
        liveSettingsSnapshot.store(settings)

        do {
            try settingsStore.save(settings)
        } catch {
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    func refreshOnboardingPrerequisites() {
        refreshCameraAuthorizationStatus()
        extensionManager.refreshStatus()

        if cameraAuthorizationStatus == .authorized {
            startPreviewIfNeeded()
        }
    }

    func requestCameraAccessFromOnboarding() {
        refreshCameraAuthorizationStatus()

        switch cameraAuthorizationStatus {
        case .authorized:
            startPreviewIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.refreshCameraAuthorizationStatus()
                    if granted {
                        self.startPreviewIfNeeded()
                    } else {
                        self.clearPreviewSignalMonitoring()
                        self.statusMessage = "Camera access denied."
                    }
                }
            }
        default:
            clearPreviewSignalMonitoring()
            statusMessage = "Camera access denied."
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        showingOnboarding = false
        persistSettings()
        refreshOnboardingPrerequisites()
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        showingSettings = false
        showingOnboarding = true
        persistSettings()
        refreshOnboardingPrerequisites()
        if cameraAuthorizationStatus == .notDetermined {
            stopPreview()
        }
    }

    func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func openExtensionApprovalSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func startPreviewIfNeeded() {
        guard cameraAuthorizationStatus == .authorized else { return }
        guard pipelineActivity == nil, !hasPreviewFrame else { return }
        startPreview()
    }

    func switchToSuggestedCamera() {
        if let suggestedRecoveryCamera {
            selectedCameraID = suggestedRecoveryCamera.uniqueID
            applyCameraSelection()
            return
        }

        retrySelectedCamera()
    }

    func retrySelectedCamera() {
        refreshCameras()
        persistSettings()
        let settings = currentSettings

        guard settings.cameraID != nil else {
            clearPreviewSignalMonitoring()
            statusMessage = "No camera available."
            return
        }

        runPipelineOperation(activity: .starting, clearsPreview: true) { pipeline in
            await pipeline.stopAsync()
            try await pipeline.startAsync(cameraID: settings.cameraID, settings: settings)
        }
    }

    private func requestCameraAccessAndStartPreview() {
        refreshCameraAuthorizationStatus()

        switch cameraAuthorizationStatus {
        case .authorized:
            startPreviewIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.refreshCameraAuthorizationStatus()
                    if granted {
                        self.startPreviewIfNeeded()
                    } else {
                        self.clearPreviewSignalMonitoring()
                        self.statusMessage = "Camera access denied."
                    }
                }
            }
        default:
            clearPreviewSignalMonitoring()
            statusMessage = "Camera access denied."
        }
    }

    private func refreshCameraAuthorizationStatus() {
        cameraAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
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

    private func startPreviewSignalTimer() {
        guard previewSignalTimer == nil else { return }

        previewSignalTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.evaluatePreviewSignal()
            }
        }
    }

    private func publishFrameStatistics(_ frameStatistics: FrameStatistics, hasFace: Bool) {
        guard pipelineActivity == nil else { return }

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
        previewState = .live
        statusMessage = hasFace ? "Preview running — tracking face" : "Preview running — no face found"
    }

    private func makePipelineIfNeeded() -> AutoFramePipeline {
        if let pipeline {
            return pipeline
        }

        let pipeline = AutoFramePipeline(
            settingsProvider: { [liveSettingsSnapshot] in
                liveSettingsSnapshot.load()
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

        self.pipeline = pipeline
        return pipeline
    }

    private func runPipelineOperation(
        activity: PipelineActivity,
        clearsPreview: Bool,
        operation: @escaping @Sendable (AutoFramePipeline) async throws -> Void
    ) {
        pipelineOperationTask?.cancel()
        pipelineOperationID += 1
        let operationID = pipelineOperationID
        let pipeline = makePipelineIfNeeded()

        pipelineActivity = activity
        statusMessage = activity.statusMessage

        if clearsPreview {
            resetPreviewForAwaitingFrames()
            clearPreviewSignalMonitoring()
        }

        pipelineOperationTask = Task { [weak self, pipeline] in
            do {
                try await operation(pipeline)
                await MainActor.run {
                    guard let self, self.pipelineOperationID == operationID else { return }
                    self.pipelineActivity = nil
                    if self.hasPreviewFrame {
                        self.previewState = .live
                        if self.statusMessage == activity.statusMessage {
                            self.statusMessage = "Preview running."
                        }
                    } else {
                        self.beginWaitingForPreviewFrames()
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.pipelineOperationID == operationID else { return }
                    self.pipelineActivity = nil
                    self.clearPreviewSignalMonitoring()
                    self.statusMessage = "Preview failed: \(error)"
                }
                NSLog("[AutoFrame] Preview operation failed: %@", "\(error)")
            }
        }
    }

    private func resetPreviewForAwaitingFrames() {
        previewStream.reset()
        hasPreviewFrame = false
        previewFPS = 0
        previewState = .idle
        lastStatsUIUpdateTime = .zero
        lastFacePresence = nil
    }

    private func beginWaitingForPreviewFrames() {
        previewSignalMonitor.begin()
        previewState = .warmingUp
        statusMessage = "Waiting for video from \(selectedCameraStatusName)…"
    }

    private func clearPreviewSignalMonitoring() {
        previewSignalMonitor.stop()
        previewState = .idle
    }

    private func recordPreviewFrame(at time: CFAbsoluteTime) {
        previewSignalMonitor.recordFrame(at: time)
        hasPreviewFrame = true

        if previewState != .live {
            previewState = .live
            if statusMessage.hasPrefix("No signal from ") || statusMessage.hasPrefix("Waiting for video from ") {
                statusMessage = "Preview running."
            }
        }
    }

    private func evaluatePreviewSignal() {
        guard pipelineActivity == nil else { return }

        switch previewSignalMonitor.state() {
        case .idle:
            return
        case .warmingUp:
            if previewState != .warmingUp {
                previewState = .warmingUp
                statusMessage = "Waiting for video from \(selectedCameraStatusName)…"
            }
        case .live:
            if previewState != .live {
                previewState = .live
            }
        case let .noSignal(reason):
            enterNoSignalState(reason)
        }
    }

    private func enterNoSignalState(_ reason: PreviewSignalMonitor.NoSignalReason) {
        guard previewState != .noSignal(reason) else { return }

        previewState = .noSignal(reason)
        hasPreviewFrame = false
        previewFPS = 0
        previewStream.reset()
        statusMessage = "No signal from \(selectedCameraStatusName)."
    }

    private var selectedCamera: CameraDeviceDescriptor? {
        cameras.first(where: { $0.uniqueID == selectedCameraID })
    }

    private var selectedCameraStatusName: String {
        selectedCamera?.localizedName ?? "the selected camera"
    }
}

extension AppModel {
    enum PipelineActivity: Equatable {
        case starting
        case switchingCamera
        case changingResolution(OutputResolution)

        var title: String {
            switch self {
            case .starting:
                return "Starting preview"
            case .switchingCamera:
                return "Switching camera"
            case let .changingResolution(output):
                return "Applying \(output.displayName)"
            }
        }

        var detail: String {
            switch self {
            case .starting:
                return "Preparing capture session and first frames."
            case .switchingCamera:
                return "Reconnecting the selected input and rebuilding the processing graph."
            case .changingResolution:
                return "Updating capture format without freezing the whole interface."
            }
        }

        var statusMessage: String {
            "\(title)…"
        }
    }

    enum PreviewState: Equatable {
        case idle
        case warmingUp
        case live
        case noSignal(PreviewSignalMonitor.NoSignalReason)
    }
}

private final class LiveSettingsSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AutoFrameSettings

    init(_ settings: AutoFrameSettings) {
        self.settings = settings
    }

    func load() -> AutoFrameSettings {
        lock.withLock {
            settings
        }
    }

    func store(_ settings: AutoFrameSettings) {
        lock.withLock {
            self.settings = settings
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
