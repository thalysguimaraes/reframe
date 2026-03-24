import AutoFrameCore
import CoreVideo
import Foundation
import SystemExtensions

enum HeadlessSystemExtensionCommand {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        if arguments.contains("--activate-extension") {
            let runner = ActivationRequestRunner()
            return runner.run()
        }

        if arguments.contains("--publish-preview-headless") {
            let publisher = HeadlessPreviewPublisher(arguments: arguments)
            return publisher.run()
        }

        if arguments.contains("--publish-test-pattern") {
            let publisher = TestPatternPublisher(arguments: arguments)
            return publisher.run()
        }

        return nil
    }
}

private final class ActivationRequestRunner: NSObject, OSSystemExtensionRequestDelegate {
    private let semaphore = DispatchSemaphore(value: 0)
    private var exitCode: Int32 = 1
    private var output = ""

    func run() -> Int32 {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: AppConstants.extensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)

        while semaphore.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }

        let handle = exitCode == 0 ? FileHandle.standardOutput : FileHandle.standardError
        if let data = (output + "\n").data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }

        return exitCode
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        output = "Extension approval required in System Settings > General > Login Items & Extensions > Camera Extensions."
        exitCode = 2
        semaphore.signal()
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            output = "Extension activation completed."
            exitCode = 0
        case .willCompleteAfterReboot:
            output = "Extension activation will complete after a reboot."
            exitCode = 0
        @unknown default:
            output = "Extension activation finished with an unknown result."
            exitCode = 1
        }

        semaphore.signal()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        output = "Extension activation failed: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
        exitCode = 1
        semaphore.signal()
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }
}

private final class HeadlessPreviewPublisher {
    private let arguments: [String]
    private let frameStore = SharedVideoFrameStore.shared
    private let settingsStore = SharedSettingsStore.shared
    private let statsStore = SharedStatsStore.shared

    private var pipeline: AutoFramePipeline?
    private var publishedFrameCount = 0

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() -> Int32 {
        var settings = settingsStore.load()

        if let outputName = optionValue(named: "--output"),
           let output = OutputResolution(rawValue: outputName.lowercased()) {
            settings.outputResolution = output
        }

        if let trackingValue = optionValue(named: "--tracking") {
            settings.trackingEnabled = ["1", "true", "yes", "on"].contains(trackingValue.lowercased())
        }

        if let cameraQuery = optionValue(named: "--camera") {
            settings.cameraID = cameraID(matching: cameraQuery)
        }

        let cameraID = CameraCatalog.defaultPhysicalCameraID(preferredID: settings.cameraID)
        guard cameraID != nil else {
            fputs("No physical camera available for headless publishing.\n", stderr)
            return 1
        }

        let duration = optionValue(named: "--duration").flatMap(Double.init) ?? 15
        let pipeline = AutoFramePipeline(
            settingsProvider: { settings },
            statsStore: statsStore
        )

        pipeline.onProcessedFrame = { [weak self] frame in
            guard let self else { return }
            self.frameStore.publish(frame.pixelBuffer)
            self.publishedFrameCount += 1
        }

        do {
            try pipeline.start(cameraID: cameraID)
            self.pipeline = pipeline
        } catch {
            fputs("Failed to start headless preview publisher: \(error)\n", stderr)
            return 1
        }

        let deadline = Date(timeIntervalSinceNow: duration)
        while Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date(timeIntervalSinceNow: 0.1)))
        }

        pipeline.stop()
        frameStore.clear()
        print("Published \(publishedFrameCount) processed frame(s) in \(duration)s.")
        return publishedFrameCount > 0 ? 0 : 1
    }

    private func optionValue(named name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    private func cameraID(matching query: String) -> String? {
        let cameras = CameraCatalog.videoDevices()
        if let exact = cameras.first(where: { $0.uniqueID == query || $0.localizedName == query }) {
            return exact.uniqueID
        }

        return cameras.first(where: { $0.localizedName.localizedCaseInsensitiveContains(query) })?.uniqueID
    }
}

private final class TestPatternPublisher {
    private let arguments: [String]
    private let frameStore = SharedVideoFrameStore.shared

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func run() -> Int32 {
        let outputResolution: OutputResolution
        if let outputName = optionValue(named: "--output"),
           let parsedOutput = OutputResolution(rawValue: outputName.lowercased()) {
            outputResolution = parsedOutput
        } else {
            outputResolution = .hd1080
        }

        let duration = optionValue(named: "--duration").flatMap(Double.init) ?? 15
        let frameInterval = 1.0 / outputResolution.preferredFrameRate
        let deadline = Date(timeIntervalSinceNow: duration)
        var frameIndex = 0

        while Date() < deadline {
            autoreleasepool {
                if let pixelBuffer = makePatternFrame(size: outputResolution.size, frameIndex: frameIndex) {
                    frameStore.publish(pixelBuffer)
                    frameIndex += 1
                }
            }

            Thread.sleep(forTimeInterval: frameInterval)
        }

        frameStore.clear()
        print("Published \(frameIndex) test-pattern frame(s) in \(duration)s.")
        return frameIndex > 0 ? 0 : 1
    }

    private func makePatternFrame(size: CGSize, frameIndex: Int) -> CVPixelBuffer? {
        let width = Int(size.width)
        let height = Int(size.height)
        let attributes: [CFString: Any] = [
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey: width
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        let squareSize = max(64, min(width, height) / 6)
        let squareX = (frameIndex * 24) % max(1, width - squareSize)
        let squareY = (frameIndex * 16) % max(1, height - squareSize)

        for y in 0..<height {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let offset = x * 4
                let inSquare = x >= squareX && x < squareX + squareSize && y >= squareY && y < squareY + squareSize
                let blue = inSquare ? UInt8(255) : UInt8((x * 255) / max(width - 1, 1))
                let green = inSquare ? UInt8(255) : UInt8((y * 255) / max(height - 1, 1))
                let red = inSquare ? UInt8(255) : UInt8((frameIndex * 7) % 256)

                row[offset + 0] = blue
                row[offset + 1] = green
                row[offset + 2] = red
                row[offset + 3] = 255
            }
        }

        return pixelBuffer
    }

    private func optionValue(named name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }
}
