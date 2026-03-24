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
    private let relayQueue = DispatchQueue(label: "dev.autoframe.camera-extension.relay", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "dev.autoframe.camera-extension.state")
    private let reframer = PixelBufferReframer()

    private var activeStreamCount = 0
    private var lastRelayLogMessage = ""
    private var lastRelayLogTime: CFAbsoluteTime = .zero
    private var outputResolution: OutputResolution = .hd720
    private var placeholderBuffers: [OutputResolution: CVPixelBuffer] = [:]
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
            deviceProperties.model = "AutoFrame Cam Virtual Camera"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    func startStreaming(outputResolution: OutputResolution) {
        var timerToStart: DispatchSourceTimer?
        stateQueue.sync {
            activeStreamCount += 1
            self.outputResolution = outputResolution
            guard streamingTimer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: relayQueue)
            timer.schedule(
                deadline: .now(),
                repeating: outputResolution.frameDuration.dispatchInterval,
                leeway: .milliseconds(4)
            )
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
        }

        timerToCancel?.cancel()
        if timerToCancel != nil {
            logger.info("Stopped virtual camera relay.")
        }
    }

    func updateStreamingResolution(_ outputResolution: OutputResolution) {
        stateQueue.sync {
            self.outputResolution = outputResolution
        }
    }

    private func relayNextFrame() {
        let outputResolution = stateQueue.sync { self.outputResolution }
        let pixelBuffer = loadOutputPixelBuffer(for: outputResolution) ?? placeholderBuffer(for: outputResolution)
        guard let pixelBuffer else { return }
        send(pixelBuffer: pixelBuffer)
    }

    private func loadOutputPixelBuffer(for outputResolution: OutputResolution) -> CVPixelBuffer? {
        guard let snapshot = frameStore.loadLatest(maximumAge: 1.0) else {
            logRelay(message: "Relay waiting for a recent shared frame from the host app.")
            return nil
        }

        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(snapshot.pixelBuffer),
            height: CVPixelBufferGetHeight(snapshot.pixelBuffer)
        )
        guard sourceSize != .zero else { return nil }
        guard sourceSize != outputResolution.size else {
            logRelay(
                message: "Relay streaming shared frame seq \(snapshot.descriptor.sequenceNumber) at \(Int(sourceSize.width))x\(Int(sourceSize.height))."
            )
            return snapshot.pixelBuffer
        }

        let fullFrame = CGRect(origin: .zero, size: sourceSize)
        let scaledBuffer = reframer.render(
            pixelBuffer: snapshot.pixelBuffer,
            cropRect: fullFrame,
            outputSize: outputResolution.size
        )
        if scaledBuffer != nil {
            logRelay(
                message: "Relay scaling shared frame seq \(snapshot.descriptor.sequenceNumber) from \(Int(sourceSize.width))x\(Int(sourceSize.height)) to \(Int(outputResolution.size.width))x\(Int(outputResolution.size.height))."
            )
        } else {
            logRelay(message: "Relay failed to scale the shared frame.", level: .error)
        }
        return scaledBuffer
    }

    private func send(pixelBuffer: CVPixelBuffer) {
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
}

final class AutoFrameCameraStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!

    let device: CMIOExtensionDevice
    private let streamFormats: [CMIOExtensionStreamFormat]

    init(localizedName: String, streamID: UUID, device: CMIOExtensionDevice) {
        self.device = device
        self.streamFormats = OutputResolution.allCases.map { resolution in
            var description: CMFormatDescription?
            let size = resolution.size
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
                maxFrameDuration: resolution.frameDuration,
                minFrameDuration: resolution.frameDuration,
                validFrameDurations: [resolution.frameDuration]
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
            propertiesState.frameDuration = currentResolution.frameDuration
        }

        return propertiesState
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
            (device.source as? AutoFrameCameraDeviceSource)?.updateStreamingResolution(currentResolution)
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? AutoFrameCameraDeviceSource else {
            fatalError("Unexpected CMIO device source.")
        }
        deviceSource.startStreaming(outputResolution: currentResolution)
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? AutoFrameCameraDeviceSource else {
            fatalError("Unexpected CMIO device source.")
        }
        deviceSource.stopStreaming()
    }

    private var currentResolution: OutputResolution {
        OutputResolution.allCases[safe: activeFormatIndex] ?? .hd1080
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
