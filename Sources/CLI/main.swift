import AutoFrameCore
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
case "start":
    start(arguments: Array(arguments.dropFirst()))
case "set":
    set(arguments: Array(arguments.dropFirst()))
case "toggle-tracking":
    toggleTracking(arguments: Array(arguments.dropFirst()))
case "print-stats", "stats":
    printStats()
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

func cameraID(matching nameOrID: String) -> String? {
    let cameras = CameraCatalog.videoDevices()
    if let exact = cameras.first(where: { $0.uniqueID == nameOrID || $0.localizedName == nameOrID }) {
        return exact.uniqueID
    }
    return cameras.first(where: { $0.localizedName.localizedCaseInsensitiveContains(nameOrID) })?.uniqueID
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
      \(AppConstants.cliExecutableName) start --camera <name-or-id> --preset <tight|medium|wide> --output <720p|1080p>
      \(AppConstants.cliExecutableName) set --smoothing <value> --zoom-strength <0...1> [--preset <tight|medium|wide>] [--tracking on|off]
      \(AppConstants.cliExecutableName) toggle-tracking [on|off]
      \(AppConstants.cliExecutableName) print-stats
      \(AppConstants.cliExecutableName) stop
    """)
}
