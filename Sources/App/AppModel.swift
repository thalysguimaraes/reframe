import AutoFrameCore
@preconcurrency import AVFoundation
import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
    @Published var virtualBackgroundMode: VirtualBackgroundMode
    @Published var virtualBackgroundGradient: GradientPreset
    @Published var customBackgrounds: [CustomBackground]
    @Published var selectedCustomBackgroundID: String?
    @Published var hasPreviewFrame = false
    @Published var previewFPS = 0.0
    @Published var normalizedFaceRect: CGRect?
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
    @Published var showInMenuBar: Bool
    @Published var showDockIcon: Bool
    @Published var keepRunningOnClose: Bool
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
    private var preferredDarkMode: Bool?
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
        self.virtualBackgroundMode = settings.virtualBackgroundMode
        self.virtualBackgroundGradient = settings.virtualBackgroundGradient
        self.customBackgrounds = settings.customBackgrounds
        self.selectedCustomBackgroundID = settings.selectedCustomBackgroundID
        self.zoomEnabled = settings.zoomStrength > 0
        self.exposure = settings.exposure
        self.contrast = settings.contrast
        self.temperature = settings.temperature
        self.tint = settings.tint
        self.vibrance = settings.vibrance
        self.saturation = settings.saturation
        self.sharpness = settings.sharpness
        self.showInMenuBar = settings.showInMenuBar
        self.showDockIcon = settings.showDockIcon
        self.keepRunningOnClose = settings.keepRunningOnClose
        self.preferredDarkMode = settings.preferredDarkMode
        self.isDarkMode = settings.preferredDarkMode ?? Self.systemPrefersDarkMode
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

    var shouldKeepRunningInBackground: Bool {
        showInMenuBar
    }

    var menuBarIconSymbolName: String {
        if pipelineActivity != nil {
            return "camera.badge.ellipsis"
        }

        switch previewState {
        case .live:
            return "camera.fill"
        case .warmingUp:
            return "camera.badge.ellipsis"
        case .noSignal:
            return "camera.slash.fill"
        case .idle:
            return "camera"
        }
    }

    var menuBarIconTintColor: NSColor {
        if pipelineActivity != nil {
            return .systemOrange
        }

        switch previewState {
        case .live:
            return .systemGreen
        case .warmingUp:
            return .systemOrange
        case .noSignal:
            return .systemRed
        case .idle:
            return .secondaryLabelColor
        }
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
            virtualBackgroundMode: virtualBackgroundMode,
            virtualBackgroundGradient: virtualBackgroundGradient,
            customBackgrounds: customBackgrounds,
            selectedCustomBackgroundID: selectedCustomBackgroundID,
            performancePolicy: performancePolicy,
            exposure: exposure,
            contrast: contrast,
            temperature: temperature,
            tint: tint,
            vibrance: vibrance,
            saturation: saturation,
            sharpness: sharpness,
            showInMenuBar: showInMenuBar,
            showDockIcon: showDockIcon,
            keepRunningOnClose: keepRunningOnClose,
            preferredDarkMode: preferredDarkMode
        )
    }

    func setDarkMode(_ enabled: Bool) {
        preferredDarkMode = enabled
        isDarkMode = enabled
        persistSettings()
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

    func enableVirtualBackground(mode: VirtualBackgroundMode) {
        virtualBackgroundMode = mode
        if mode != .off {
            portraitModeEnabled = false
        }
        persistSettings()
    }

    func enablePortraitMode(_ enabled: Bool) {
        portraitModeEnabled = enabled
        if enabled {
            virtualBackgroundMode = .off
        }
        persistSettings()
    }

    func importVirtualBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background image"

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self.copyAndApplyBackgroundImage(from: url)
            }
        }
    }

    private func copyAndApplyBackgroundImage(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let nextIndex = customBackgrounds.count + 1
        let id = UUID().uuidString
        let fileName = "virtual-bg-\(id).\(url.pathExtension)"
        let container = SharedStorage.containerDirectory()
        let dest = container.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: url, to: dest)
            let bg = CustomBackground(id: id, name: "Custom \(nextIndex)", fileName: fileName)
            customBackgrounds.append(bg)
            selectedCustomBackgroundID = id
            virtualBackgroundMode = .customImage
            portraitModeEnabled = false
            persistSettings()
        } catch {
            NSLog("[AutoFrame] Failed to copy background image: %@", "\(error)")
        }
    }

    func selectCustomBackground(_ id: String) {
        selectedCustomBackgroundID = id
        virtualBackgroundMode = .customImage
        portraitModeEnabled = false
        persistSettings()
    }

    func removeCustomBackground(_ id: String) {
        guard let bg = customBackgrounds.first(where: { $0.id == id }) else { return }
        let container = SharedStorage.containerDirectory()
        let path = container.appendingPathComponent(bg.fileName)
        try? FileManager.default.removeItem(at: path)
        customBackgrounds.removeAll { $0.id == id }
        if selectedCustomBackgroundID == id {
            selectedCustomBackgroundID = nil
            if virtualBackgroundMode == .customImage {
                virtualBackgroundMode = customBackgrounds.isEmpty ? .off : .gradient
            }
        }
        persistSettings()
    }

    func renameCustomBackground(_ id: String, to newName: String) {
        guard let index = customBackgrounds.firstIndex(where: { $0.id == id }) else { return }
        customBackgrounds[index].name = newName
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

    func reinstallExtension() {
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

    private func publishFrameStatistics(_ frameStatistics: FrameStatistics, hasFace: Bool, faceRect: CGRect?) {
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
        normalizedFaceRect = faceRect
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
                let normalizedFace: CGRect? = {
                    guard let face = frame.detectedFace else { return nil }
                    let crop = frame.cropRect
                    guard crop.width > 0, crop.height > 0 else { return nil }
                    return CGRect(
                        x: (face.rect.minX - crop.minX) / crop.width,
                        y: (face.rect.minY - crop.minY) / crop.height,
                        width: face.rect.width / crop.width,
                        height: face.rect.height / crop.height
                    )
                }()
                self.publishFrameStatistics(frame.statistics, hasFace: frame.detectedFace != nil, faceRect: normalizedFace)
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
