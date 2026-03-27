import AutoFrameCore
@preconcurrency import AVFoundation
import CoreMedia
import Foundation

let settingsStore = SharedSettingsStore.shared
let statsStore = SharedStatsStore.shared
let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(0)
}

switch command {
case "list-cameras":
    listCameras()
case "probe-virtual-camera":
    probeVirtualCamera(arguments: Array(arguments.dropFirst()))
case "start":
    start(arguments: Array(arguments.dropFirst()))
case "set":
    set(arguments: Array(arguments.dropFirst()))
case "toggle-tracking":
    toggleTracking(arguments: Array(arguments.dropFirst()))
case "print-stats", "stats":
    printStats()
case "print-demand", "demand":
    printDemand()
case "stop":
    stop()
default:
    printUsage()
}

func listCameras() {
    let cameras = CameraCatalog.videoDevices()
    guard !cameras.isEmpty else {
        print("No physical cameras found.")
        return
    }

    for camera in cameras {
        print("\(camera.localizedName)\n  id: \(camera.uniqueID)\n  \(camera.label)")
    }
}

func probeVirtualCamera(arguments: [String]) {
    let duration = optionValue(named: "--duration", in: arguments).flatMap(Double.init) ?? 8
    let query = optionValue(named: "--camera", in: arguments)
    let timestampFormatter = ISO8601DateFormatter()
    let startedAt = Date()

    guard let device = virtualCameraDevice(matching: query) else {
        fputs("Virtual camera not found.\n", stderr)
        fputs("Visible video devices:\n\(allVideoDevicesSummary())\n", stderr)
        exit(1)
    }

    print("""
    probe_started_at: \(timestampFormatter.string(from: startedAt))
    device_name: \(device.localizedName)
    device_id: \(device.uniqueID)
    manufacturer: \(device.manufacturer)
    model_id: \(device.modelID)
    duration_s: \(String(format: "%.1f", duration))
    """)

    do {
        let probe = try VirtualCameraConsumerProbe(device: device)
        let result = probe.run(duration: duration)
        let stats = statsStore.load()
        let demand = SharedVirtualCameraDemandStore.shared.currentSnapshot()

        print("frames_received: \(result.frameCount)")
        if let latency = result.firstFrameLatency {
            print("first_frame_latency_ms: \(Int((latency * 1000).rounded()))")
        } else {
            print("first_frame_latency_ms: none")
        }
        if let latency = result.firstNonDarkFrameLatency {
            print("first_non_dark_frame_latency_ms: \(Int((latency * 1000).rounded()))")
        } else {
            print("first_non_dark_frame_latency_ms: none")
        }
        if let dimensions = result.lastFrameDimensions {
            print("last_frame_dimensions: \(dimensions.width)x\(dimensions.height)")
        } else {
            print("last_frame_dimensions: none")
        }
        let minimumLuma = String(format: "%.3f", result.minimumMeanLuma)
        let maximumLuma = String(format: "%.3f", result.maximumMeanLuma)
        print("frame_mean_luma_range: \(minimumLuma)...\(maximumLuma)")
        print("unique_frame_signatures: \(result.uniqueFrameSignatureCount)")
        print("session_running_latency_ms: \(Int((result.sessionStartLatency * 1000).rounded()))")
        print("demand_active_consumers: \(demand.activeConsumerCount)")
        print("demand_last_heartbeat_at: \(timestampFormatter.string(from: demand.lastHeartbeatAt))")
        if let stats {
            print("host_capture_fps: \(String(format: "%.1f", stats.captureFPS))")
            print("host_processing_fps: \(String(format: "%.1f", stats.processingFPS))")
            print("host_relay_fps: \(String(format: "%.1f", stats.relayFPS))")
            print("host_output_dimensions: \(stats.outputWidth)x\(stats.outputHeight)")
        } else {
            print("host_stats: unavailable")
        }

        exit(result.frameCount > 0 ? 0 : 2)
    } catch {
        fputs("Failed to probe virtual camera: \(error)\n", stderr)
        exit(1)
    }
}

func start(arguments: [String]) {
    var settings = settingsStore.load()

    if let camera = optionValue(named: "--camera", in: arguments) {
        settings.cameraID = cameraID(matching: camera)
    }
    if let preset = optionValue(named: "--preset", in: arguments), let framingPreset = FramingPreset(rawValue: preset.lowercased()) {
        settings.framingPreset = framingPreset
    }
    if let output = optionValue(named: "--output", in: arguments), let resolution = OutputResolution(rawValue: output.lowercased()) {
        settings.outputResolution = resolution
    }

    settings.trackingEnabled = true
    save(settings)
    print("Saved start configuration for \(settings.cameraID ?? "default camera").")
}

func set(arguments: [String]) {
    var settings = settingsStore.load()

    if let smoothing = optionValue(named: "--smoothing", in: arguments).flatMap(Double.init) {
        settings.smoothing = min(max(smoothing, 0.0), 0.99)
    }
    if let zoom = optionValue(namedAnyOf: ["--zoom", "--zoom-strength"], in: arguments).flatMap(Double.init) {
        settings.zoomStrength = min(max(zoom, 0.0), 1.0)
    }
    if let deadzone = optionValue(named: "--deadzone", in: arguments).flatMap(Double.init) {
        settings.deadZone = min(max(deadzone, 0.0), 0.25)
    }
    if let preset = optionValue(named: "--preset", in: arguments), let framingPreset = FramingPreset(rawValue: preset.lowercased()) {
        settings.framingPreset = framingPreset
    }
    if let tracking = optionValue(named: "--tracking", in: arguments) {
        settings.trackingEnabled = ["1", "true", "on", "yes"].contains(tracking.lowercased())
    }

    save(settings)
    print("Updated configuration.")
}

func toggleTracking(arguments: [String]) {
    var settings = settingsStore.load()
    if let mode = arguments.first {
        settings.trackingEnabled = ["1", "true", "on", "yes"].contains(mode.lowercased())
    } else {
        settings.trackingEnabled.toggle()
    }
    save(settings)
    print("Tracking \(settings.trackingEnabled ? "enabled" : "disabled").")
}

func stop() {
    var settings = settingsStore.load()
    settings.trackingEnabled = false
    save(settings)
    print("Tracking disabled. The extension will publish a wide frame until tracking is re-enabled.")
}

func printStats() {
    guard let stats = statsStore.load() else {
        print("No stats have been published yet.")
        return
    }

    print("""
    timestamp: \(stats.timestamp)
    capture_fps: \(String(format: "%.1f", stats.captureFPS))
    processing_fps: \(String(format: "%.1f", stats.processingFPS))
    relay_fps: \(String(format: "%.1f", stats.relayFPS))
    target_fps: \(String(format: "%.1f", stats.targetFPS))
    face_confidence: \(String(format: "%.2f", stats.faceConfidence))
    crop_coverage: \(String(format: "%.2f", stats.cropCoverage * 100))%
    adaptive_quality: \(stats.adaptiveQualityActive ? "on" : "off")
    detection_stride: \(stats.detectionStride)
    segmentation_stride: \(stats.segmentationStride)
    source: \(stats.sourceWidth)x\(stats.sourceHeight)
    output: \(stats.outputWidth)x\(stats.outputHeight)
    """)
}

func printDemand() {
    let snapshot = SharedVirtualCameraDemandStore.shared.currentSnapshot()

    print("""
    active_consumers: \(snapshot.activeConsumerCount)
    last_heartbeat_at: \(snapshot.lastHeartbeatAt)
    last_updated_at: \(snapshot.lastUpdatedAt)
    has_active_consumers: \(snapshot.hasActiveConsumers() ? "true" : "false")
    """)
}

func cameraID(matching nameOrID: String) -> String? {
    let cameras = CameraCatalog.videoDevices()
    if let exact = cameras.first(where: { $0.uniqueID == nameOrID || $0.localizedName == nameOrID }) {
        return exact.uniqueID
    }
    return cameras.first(where: { $0.localizedName.localizedCaseInsensitiveContains(nameOrID) })?.uniqueID
}

func virtualCameraDevice(matching nameOrID: String?) -> AVCaptureDevice? {
    let devices = allVideoDevices()

    if let nameOrID {
        if let exact = devices.first(where: { $0.uniqueID == nameOrID || $0.localizedName == nameOrID }) {
            return exact
        }

        let normalizedQuery = normalizedCameraValue(nameOrID)
        if let fuzzyMatch = devices.first(where: {
            normalizedCameraValue($0.localizedName).contains(normalizedQuery) ||
            normalizedCameraValue($0.uniqueID).contains(normalizedQuery) ||
            normalizedCameraValue($0.manufacturer).contains(normalizedQuery) ||
            normalizedCameraValue($0.modelID).contains(normalizedQuery)
        }) {
            return fuzzyMatch
        }
    }

    return devices.first(where: isVirtualReframeCamera)
}

func allVideoDevices() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
        deviceTypes: [.externalUnknown, .builtInWideAngleCamera],
        mediaType: .video,
        position: .unspecified
    ).devices
}

func allVideoDevicesSummary() -> String {
    let devices = allVideoDevices()
    guard !devices.isEmpty else {
        return "  (none)"
    }

    return devices.map {
        "  \($0.localizedName) | id=\($0.uniqueID) | manufacturer=\($0.manufacturer) | model=\($0.modelID)"
    }.joined(separator: "\n")
}

func isVirtualReframeCamera(_ device: AVCaptureDevice) -> Bool {
    let normalizedName = normalizedCameraValue(device.localizedName)
    let normalizedManufacturer = normalizedCameraValue(device.manufacturer)
    let normalizedModel = normalizedCameraValue(device.modelID)
    let normalizedUniqueID = normalizedCameraValue(device.uniqueID)

    let knownNames = Set(([AppConstants.virtualCameraName] + AppConstants.legacyVirtualCameraNames).map(normalizedCameraValue))
    let knownManufacturers = Set(AppConstants.virtualCameraManufacturers.map(normalizedCameraValue))
    let knownModels = AppConstants.virtualCameraModelNames.map(normalizedCameraValue)

    if knownNames.contains(normalizedName) || knownNames.contains(normalizedUniqueID) {
        return true
    }

    if knownManufacturers.contains(normalizedManufacturer) {
        return true
    }

    return knownModels.contains { normalizedModel.contains($0) }
}

func normalizedCameraValue(_ value: String) -> String {
    value
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func optionValue(named name: String, in arguments: [String]) -> String? {
    optionValue(namedAnyOf: [name], in: arguments)
}

func optionValue(namedAnyOf names: [String], in arguments: [String]) -> String? {
    for name in names {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            continue
        }
        return arguments[index + 1]
    }
    return nil
}

func save(_ settings: AutoFrameSettings) {
    do {
        try settingsStore.save(settings)
    } catch {
        fputs("Failed to save settings: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func printUsage() {
    print("""
    Usage:
      \(AppConstants.cliExecutableName) list-cameras
      \(AppConstants.cliExecutableName) probe-virtual-camera [--camera <name-or-id>] [--duration <seconds>]
      \(AppConstants.cliExecutableName) start --camera <name-or-id> --preset <tight|medium|wide> --output <720p|1080p>
      \(AppConstants.cliExecutableName) set --smoothing <value> --zoom-strength <0...1> [--preset <tight|medium|wide>] [--tracking on|off]
      \(AppConstants.cliExecutableName) toggle-tracking [on|off]
      \(AppConstants.cliExecutableName) print-stats
      \(AppConstants.cliExecutableName) print-demand
      \(AppConstants.cliExecutableName) stop
    """)
}

final class VirtualCameraConsumerProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let outputQueue = DispatchQueue(label: "dev.autoframe.reframe.cli.virtual-camera-probe")
    private let lock = NSLock()

    private var firstFrameDate: Date?
    private var firstNonDarkFrameDate: Date?
    private var frameCount = 0
    private var lastFrameDimensions: CMVideoDimensions?
    private var minimumMeanLuma = Double.greatestFiniteMagnitude
    private var maximumMeanLuma = 0.0
    private var uniqueFrameSignatures: Set<UInt64> = []

    init(device: AVCaptureDevice) throws {
        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)

        session.beginConfiguration()
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard session.canAddInput(input) else {
            throw ProbeError.cannotAddInput
        }

        guard session.canAddOutput(output) else {
            throw ProbeError.cannotAddOutput
        }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
    }

    func run(duration: TimeInterval) -> Result {
        let startedAt = Date()
        session.startRunning()
        let runningAt = Date()

        let deadline = Date(timeIntervalSinceNow: duration)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date(timeIntervalSinceNow: 0.05)))
        }

        session.stopRunning()

        return lock.withLock {
            Result(
                frameCount: frameCount,
                firstFrameLatency: firstFrameDate.map { $0.timeIntervalSince(startedAt) },
                firstNonDarkFrameLatency: firstNonDarkFrameDate.map { $0.timeIntervalSince(startedAt) },
                lastFrameDimensions: lastFrameDimensions,
                minimumMeanLuma: minimumMeanLuma.isFinite ? minimumMeanLuma : 0.0,
                maximumMeanLuma: maximumMeanLuma,
                sessionStartLatency: runningAt.timeIntervalSince(startedAt),
                uniqueFrameSignatureCount: uniqueFrameSignatures.count
            )
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = Date()
        let dimensions = CMSampleBufferGetFormatDescription(sampleBuffer).map(CMVideoFormatDescriptionGetDimensions)
        let analysis = sampleBuffer.imageBuffer.flatMap(analyzeFrame(pixelBuffer:))

        lock.withLock {
            frameCount += 1
            if firstFrameDate == nil {
                firstFrameDate = timestamp
            }
            if let dimensions {
                lastFrameDimensions = dimensions
            }
            if let analysis {
                minimumMeanLuma = min(minimumMeanLuma, analysis.meanLuma)
                maximumMeanLuma = max(maximumMeanLuma, analysis.meanLuma)
                if analysis.meanLuma > 0.03, firstNonDarkFrameDate == nil {
                    firstNonDarkFrameDate = timestamp
                }
                if uniqueFrameSignatures.count < 128 {
                    uniqueFrameSignatures.insert(analysis.signature)
                }
            }
        }
    }

    struct Result {
        let frameCount: Int
        let firstFrameLatency: TimeInterval?
        let firstNonDarkFrameLatency: TimeInterval?
        let lastFrameDimensions: CMVideoDimensions?
        let minimumMeanLuma: Double
        let maximumMeanLuma: Double
        let sessionStartLatency: TimeInterval
        let uniqueFrameSignatureCount: Int
    }

    enum ProbeError: Error {
        case cannotAddInput
        case cannotAddOutput
    }

    private func analyzeFrame(pixelBuffer: CVPixelBuffer) -> FrameAnalysis? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)

        let sampleColumns = max(8, min(32, width))
        let sampleRows = max(8, min(32, height))
        let xStride = max(1, width / sampleColumns)
        let yStride = max(1, height / sampleRows)

        var lumaTotal = 0.0
        var sampleCount = 0
        var signature: UInt64 = 1469598103934665603

        for y in stride(from: 0, to: height, by: yStride) {
            let row = bytes.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: xStride) {
                let pixel = row.advanced(by: x * 4)
                let blue = Double(pixel[0]) / 255.0
                let green = Double(pixel[1]) / 255.0
                let red = Double(pixel[2]) / 255.0
                let luma = (0.0722 * blue) + (0.7152 * green) + (0.2126 * red)
                lumaTotal += luma
                sampleCount += 1

                signature ^= UInt64(pixel[0])
                signature &*= 1099511628211
                signature ^= UInt64(pixel[1])
                signature &*= 1099511628211
                signature ^= UInt64(pixel[2])
                signature &*= 1099511628211
            }
        }

        guard sampleCount > 0 else {
            return nil
        }

        return FrameAnalysis(
            meanLuma: lumaTotal / Double(sampleCount),
            signature: signature
        )
    }

    private struct FrameAnalysis {
        let meanLuma: Double
        let signature: UInt64
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
