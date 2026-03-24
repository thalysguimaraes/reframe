import AutoFrameCore
@preconcurrency import AVFoundation
import CoreMediaIO
import CoreVideo
import Foundation
import IOKit.audio
import os.log

private let logger = Logger(subsystem: "dev.autoframe.camera-extension", category: "provider")

final class AutoFrameCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var streamSource: AutoFrameCameraStreamSource!
    private let frameStore = SharedVideoFrameStore.shared
    private let statsStore = SharedStatsStore.shared
    private let relayQueue = DispatchQueue(label: "dev.autoframe.camera-extension.relay", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "dev.autoframe.camera-extension.state")
    private let reframer = PixelBufferReframer()

    private var activeStreamCount = 0
    private var lastRelayLogMessage = ""
    private var lastRelayLogTime: CFAbsoluteTime = .zero
    private var activeFormat = VirtualCameraFormat(resolution: .hd720, frameRate: OutputResolution.hd720.preferredFrameRate)
    private var placeholderBuffers: [OutputResolution: CVPixelBuffer] = [:]
    private var relayFPSWindow: [CFAbsoluteTime] = []
    private var streamingTimer: DispatchSourceTimer?

    override init() {
        super.init()

        device = CMIOExtensionDevice(
            localizedName: AppConstants.virtualCameraName,
            deviceID: AppConstants.virtualDeviceUUID,
            legacyDeviceID: AppConstants.virtualCameraName,
            source: self
        )

        streamSource = AutoFrameCameraStreamSource(
            localizedName: "\(AppConstants.virtualCameraName).Video",
            streamID: AppConstants.virtualStreamUUID,
            device: device
        )

        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("Failed to add CMIO stream: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "Reframe Virtual Camera"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    fileprivate func startStreaming(format: VirtualCameraFormat) {
        var timerToStart: DispatchSourceTimer?
        stateQueue.sync {
            activeStreamCount += 1
            activeFormat = format
            guard streamingTimer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: relayQueue)
            schedule(timer: timer, for: format)
            timer.setEventHandler { [weak self] in
                self?.relayNextFrame()
            }
            streamingTimer = timer
            timerToStart = timer
        }

        timerToStart?.resume()
        if timerToStart != nil {
            logger.info("Started virtual camera relay.")
        }
    }

    func stopStreaming() {
        var timerToCancel: DispatchSourceTimer?
        stateQueue.sync {
            activeStreamCount = max(0, activeStreamCount - 1)
            guard activeStreamCount == 0 else { return }
            timerToCancel = streamingTimer
            streamingTimer = nil
            relayFPSWindow.removeAll(keepingCapacity: true)
        }

        timerToCancel?.cancel()
        if timerToCancel != nil {
            logger.info("Stopped virtual camera relay.")
        }
    }

    fileprivate func updateStreamingFormat(_ format: VirtualCameraFormat) {
        stateQueue.sync {
            activeFormat = format
            if let streamingTimer {
                schedule(timer: streamingTimer, for: format)
            }
        }
    }

    private func relayNextFrame() {
        let format = stateQueue.sync { activeFormat }
        let pixelBuffer = loadOutputPixelBuffer(for: format) ?? placeholderBuffer(for: format.resolution)
        guard let pixelBuffer else { return }
        send(pixelBuffer: pixelBuffer, format: format)
    }

    private func loadOutputPixelBuffer(for format: VirtualCameraFormat) -> CVPixelBuffer? {
        guard let snapshot = frameStore.loadLatest(maximumAge: 1.0) else {
            logRelay(message: "Relay waiting for a recent shared frame from the host app.")
            return nil
        }

        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(snapshot.pixelBuffer),
            height: CVPixelBufferGetHeight(snapshot.pixelBuffer)
        )
        guard sourceSize != .zero else { return nil }
        guard sourceSize != format.resolution.size else {
            logRelay(
                message: "Relay streaming shared frame seq \(snapshot.descriptor.sequenceNumber) at \(Int(sourceSize.width))x\(Int(sourceSize.height))."
            )
            return snapshot.pixelBuffer
        }

        let fullFrame = CGRect(origin: .zero, size: sourceSize)
        let scaledBuffer = reframer.render(
            pixelBuffer: snapshot.pixelBuffer,
            cropRect: fullFrame,
            outputSize: format.resolution.size
        )
        if scaledBuffer != nil {
            logRelay(
                message: "Relay scaling shared frame seq \(snapshot.descriptor.sequenceNumber) from \(Int(sourceSize.width))x\(Int(sourceSize.height)) to \(Int(format.resolution.size.width))x\(Int(format.resolution.size.height))."
            )
        } else {
            logRelay(message: "Relay failed to scale the shared frame.", level: .error)
        }
        return scaledBuffer
    }

    private func send(pixelBuffer: CVPixelBuffer, format: VirtualCameraFormat) {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard let sampleBuffer = try? SampleBufferFactory.makeSampleBuffer(
            from: pixelBuffer,
            presentationTimeStamp: now
        ) else {
            logger.error("Failed to create sample buffer for outgoing frame.")
            return
        }

        streamSource.stream.send(
            sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC))
        )

        let relayFPS = stateQueue.sync { () -> Double in
            let now = CFAbsoluteTimeGetCurrent()
            update(window: &relayFPSWindow, now: now)
            return rollingFPS(from: relayFPSWindow)
        }

        statsStore.update {
            $0.timestamp = Date()
            $0.relayFPS = relayFPS
            $0.outputWidth = Int(format.resolution.size.width)
            $0.outputHeight = Int(format.resolution.size.height)
        }
    }

    private func placeholderBuffer(for outputResolution: OutputResolution) -> CVPixelBuffer? {
        let result = stateQueue.sync { () -> (CVPixelBuffer?, String?, OSLogType?) in
            if let buffer = placeholderBuffers[outputResolution] {
                return (buffer, nil, nil)
            }

            let size = outputResolution.size
            let attributes: [CFString: Any] = [
                kCVPixelBufferHeightKey: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey: Int(size.width)
            ]

            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32BGRA,
                attributes as CFDictionary,
                &pixelBuffer
            )

            guard status == kCVReturnSuccess, let pixelBuffer else {
                return (nil, "Relay failed to create a placeholder frame.", .error)
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            placeholderBuffers[outputResolution] = pixelBuffer
            return (
                pixelBuffer,
                "Relay sending a placeholder frame at \(Int(size.width))x\(Int(size.height)).",
                .info
            )
        }

        if let message = result.1, let level = result.2 {
            logRelay(message: message, level: level)
        }

        return result.0
    }

    private func logRelay(message: String, level: OSLogType = .debug) {
        let shouldLog = stateQueue.sync {
            let now = CFAbsoluteTimeGetCurrent()
            defer {
                lastRelayLogMessage = message
                lastRelayLogTime = now
            }

            return message != lastRelayLogMessage || now - lastRelayLogTime >= 2
        }

        guard shouldLog else { return }

        switch level {
        case .error:
            logger.error("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        default:
            logger.debug("\(message, privacy: .public)")
        }
    }

    private func schedule(timer: DispatchSourceTimer, for format: VirtualCameraFormat) {
        let leeway: DispatchTimeInterval = format.frameRate >= 60 ? .milliseconds(2) : .milliseconds(4)
        timer.schedule(
            deadline: .now(),
            repeating: format.frameDuration.dispatchInterval,
            leeway: leeway
        )
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

final class AutoFrameCameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!

    let device: CMIOExtensionDevice
    private let supportedFormats: [VirtualCameraFormat]
    private let streamFormats: [CMIOExtensionStreamFormat]

    init(localizedName: String, streamID: UUID, device: CMIOExtensionDevice) {
        self.device = device
        self.supportedFormats = OutputResolution.allCases.flatMap { resolution in
            resolution.supportedFrameRates.map { VirtualCameraFormat(resolution: resolution, frameRate: $0) }
        }
        self.streamFormats = supportedFormats.map { format in
            var description: CMFormatDescription?
            let size = format.resolution.size
            CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCVPixelFormatType_32BGRA,
                width: Int32(size.width),
                height: Int32(size.height),
                extensions: nil,
                formatDescriptionOut: &description
            )
            return CMIOExtensionStreamFormat(
                formatDescription: description!,
                maxFrameDuration: format.frameDuration,
                minFrameDuration: format.frameDuration,
                validFrameDurations: [format.frameDuration]
            )
        }

        super.init()
        self.stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var activeFormatIndex = 0 {
        didSet {
            if !streamFormats.indices.contains(activeFormatIndex) {
                activeFormatIndex = 0
            }
        }
    }

    var formats: [CMIOExtensionStreamFormat] {
        streamFormats
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let propertiesState = CMIOExtensionStreamProperties(dictionary: [:])

        if properties.contains(.streamActiveFormatIndex) {
            propertiesState.activeFormatIndex = activeFormatIndex
        }

        if properties.contains(.streamFrameDuration) {
            propertiesState.frameDuration = currentFormat.frameDuration
        }

        return propertiesState
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
            (device.source as? AutoFrameCameraDeviceSource)?.updateStreamingFormat(currentFormat)
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? AutoFrameCameraDeviceSource else {
            fatalError("Unexpected CMIO device source.")
        }
        deviceSource.startStreaming(format: currentFormat)
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? AutoFrameCameraDeviceSource else {
            fatalError("Unexpected CMIO device source.")
        }
        deviceSource.stopStreaming()
    }

    private var currentFormat: VirtualCameraFormat {
        supportedFormats[safe: activeFormatIndex] ?? VirtualCameraFormat(
            resolution: .hd1080,
            frameRate: OutputResolution.hd1080.fallbackFrameRate
        )
    }
}

final class AutoFrameCameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource = AutoFrameCameraDeviceSource()

    init(clientQueue: DispatchQueue?) {
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to add CMIO device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = AppConstants.providerManufacturer
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private extension CMTime {
    var dispatchInterval: DispatchTimeInterval {
        let seconds = CMTimeGetSeconds(self)
        guard seconds.isFinite, seconds > 0 else {
            return .milliseconds(33)
        }

        return .nanoseconds(Int(seconds * Double(NSEC_PER_SEC)))
    }
}

private struct VirtualCameraFormat: Equatable {
    let resolution: OutputResolution
    let frameRate: Double

    var frameDuration: CMTime {
        resolution.frameDuration(for: frameRate)
    }
}
