import AutoFrameCore
@preconcurrency import AVFoundation
import CoreMediaIO
import CoreVideo
import Foundation
import IOKit.audio
import os.log

private let logger = Logger(subsystem: "dev.autoframe.reframe.camera-extension", category: "provider")

private func describe(client: CMIOExtensionClient) -> String {
    let signingID = client.signingID ?? "unknown"
    return "pid=\(client.pid) signingID=\(signingID) clientID=\(client.clientID.uuidString)"
}

final class ReframeCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var streamSource: ReframeCameraStreamSource!
    private let frameStore = SharedVideoFrameStore.shared
    private let statsStore = SharedStatsStore.shared
    private let virtualCameraDemandStore = SharedVirtualCameraDemandStore.shared
    private let relayQueue = DispatchQueue(label: "dev.autoframe.reframe.camera-extension.relay", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "dev.autoframe.reframe.camera-extension.state")
    private let reframer = PixelBufferReframer()
    private let preflightDemandGraceInterval: TimeInterval = 5.0

    private var activeStreamCount = 0
    private var lastRelayLogMessage = ""
    private var lastRelayLogTime: CFAbsoluteTime = .zero
    private var activeFormat = VirtualCameraFormat(resolution: .hd720, frameRate: OutputResolution.hd720.preferredFrameRate)
    private var placeholderBuffers: [OutputResolution: CVPixelBuffer] = [:]
    private var relayFPSWindow: [CFAbsoluteTime] = []
    private var demandHeartbeatTimer: DispatchSourceTimer?
    private var streamingTimer: DispatchSourceTimer?
    private var preflightDemandDeadline: Date?

    override init() {
        super.init()

        ExtensionBootstrapTrace.log("device-source: init started")
        virtualCameraDemandStore.clear()
        ExtensionBootstrapTrace.log("device-source: cleared virtual camera demand store")

        device = CMIOExtensionDevice(
            localizedName: AppConstants.virtualCameraName,
            deviceID: AppConstants.virtualDeviceUUID,
            legacyDeviceID: AppConstants.virtualCameraName,
            source: self
        )
        ExtensionBootstrapTrace.log("device-source: created CMIOExtensionDevice")

        streamSource = ReframeCameraStreamSource(
            localizedName: "\(AppConstants.virtualCameraName).Video",
            streamID: AppConstants.virtualStreamUUID,
            device: device
        )
        ExtensionBootstrapTrace.log("device-source: created stream source")

        do {
            try device.addStream(streamSource.stream)
            ExtensionBootstrapTrace.log("device-source: added stream to device")
        } catch {
            ExtensionBootstrapTrace.log("device-source: failed to add stream: \(error.localizedDescription)")
            fatalError("Failed to add CMIO stream: \(error.localizedDescription)")
        }
    }

    deinit {
        stateQueue.sync {
            demandHeartbeatTimer?.cancel()
            demandHeartbeatTimer = nil
            streamingTimer?.cancel()
            streamingTimer = nil
        }
        virtualCameraDemandStore.clear()
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
        let consumerCount = stateQueue.sync { () -> Int in
            self.activeStreamCount += 1
            activeFormat = format
            preflightDemandDeadline = nil
            let demandCount = demandConsumerCountLocked(now: Date())
            ensureDemandHeartbeatTimerLocked()
            guard streamingTimer == nil else { return demandCount }

            let timer = DispatchSource.makeTimerSource(queue: relayQueue)
            schedule(timer: timer, for: format)
            timer.setEventHandler { [weak self] in
                self?.relayNextFrame()
            }
            streamingTimer = timer
            timerToStart = timer
            return demandCount
        }

        virtualCameraDemandStore.setActiveConsumerCount(consumerCount)
        timerToStart?.resume()
        if timerToStart != nil {
            logger.info("Started virtual camera relay. activeStreamCount=\(consumerCount, privacy: .public)")
        }
    }

    fileprivate func noteClientAuthorizedToStartStream() {
        let consumerCount = stateQueue.sync { () -> Int in
            let now = Date()
            preflightDemandDeadline = now.addingTimeInterval(preflightDemandGraceInterval)
            ensureDemandHeartbeatTimerLocked()
            return demandConsumerCountLocked(now: now)
        }

        virtualCameraDemandStore.setActiveConsumerCount(consumerCount)
    }

    fileprivate func noteClientDisconnected() {
        let consumerCount = stateQueue.sync { () -> Int in
            let now = Date()
            if activeStreamCount == 0 {
                preflightDemandDeadline = nil
            }
            stopDemandHeartbeatTimerIfIdleLocked(now: now)
            return demandConsumerCountLocked(now: now)
        }

        virtualCameraDemandStore.setActiveConsumerCount(consumerCount)
    }

    func stopStreaming() {
        var timerToCancel: DispatchSourceTimer?
        let consumerCount = stateQueue.sync { () -> Int in
            self.activeStreamCount = max(0, self.activeStreamCount - 1)
            let now = Date()
            if self.activeStreamCount == 0 {
                preflightDemandDeadline = nil
            }
            let demandCount = demandConsumerCountLocked(now: now)
            stopDemandHeartbeatTimerIfIdleLocked(now: now)
            guard self.activeStreamCount == 0 else { return demandCount }
            timerToCancel = streamingTimer
            streamingTimer = nil
            relayFPSWindow.removeAll(keepingCapacity: true)
            return demandCount
        }

        virtualCameraDemandStore.setActiveConsumerCount(consumerCount)
        timerToCancel?.cancel()
        if timerToCancel != nil {
            logger.info("Stopped virtual camera relay. remainingDemandCount=\(consumerCount, privacy: .public)")
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
        let relayState = stateQueue.sync { (activeFormat, self.activeStreamCount) }
        let format = relayState.0
        let consumerCount = relayState.1

        if consumerCount > 0 {
            virtualCameraDemandStore.heartbeat(activeConsumerCount: consumerCount)
        }

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

    private func publishDemandHeartbeat() {
        let (consumerCount, shouldClearDemand) = stateQueue.sync { () -> (Int, Bool) in
            let now = Date()
            let demandCount = demandConsumerCountLocked(now: now)
            if demandCount == 0 {
                demandHeartbeatTimer?.cancel()
                demandHeartbeatTimer = nil
                return (0, true)
            }
            return (demandCount, false)
        }

        if shouldClearDemand {
            virtualCameraDemandStore.clear()
            return
        }

        virtualCameraDemandStore.heartbeat(
            activeConsumerCount: consumerCount,
            minimumInterval: 0.5
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

    private func ensureDemandHeartbeatTimerLocked() {
        guard demandHeartbeatTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: relayQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.publishDemandHeartbeat()
        }
        demandHeartbeatTimer = timer
        timer.resume()
    }

    private func stopDemandHeartbeatTimerIfIdleLocked(now: Date) {
        guard demandConsumerCountLocked(now: now) == 0 else { return }
        demandHeartbeatTimer?.cancel()
        demandHeartbeatTimer = nil
    }

    private func demandConsumerCountLocked(now: Date) -> Int {
        if activeStreamCount > 0 {
            return activeStreamCount
        }

        guard let preflightDemandDeadline, preflightDemandDeadline > now else {
            return 0
        }

        return 1
    }
}

final class ReframeCameraStreamSource: NSObject, CMIOExtensionStreamSource {
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
            (device.source as? ReframeCameraDeviceSource)?.updateStreamingFormat(currentFormat)
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        logger.info("authorizedToStartStream from \(describe(client: client), privacy: .public)")
        (device.source as? ReframeCameraDeviceSource)?.noteClientAuthorizedToStartStream()
        return true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? ReframeCameraDeviceSource else {
            fatalError("Unexpected CMIO device source.")
        }
        deviceSource.startStreaming(format: currentFormat)
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? ReframeCameraDeviceSource else {
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

final class ReframeCameraProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource = ReframeCameraDeviceSource()

    init(clientQueue: DispatchQueue?) {
        ExtensionBootstrapTrace.log("provider-source: init started")
        super.init()

        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        ExtensionBootstrapTrace.log("provider-source: created CMIOExtensionProvider")
        do {
            try provider.addDevice(deviceSource.device)
            ExtensionBootstrapTrace.log("provider-source: added device to provider")
        } catch {
            ExtensionBootstrapTrace.log("provider-source: failed to add device: \(error.localizedDescription)")
            fatalError("Failed to add CMIO device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        logger.info("Provider connect from \(describe(client: client), privacy: .public)")
    }

    func disconnect(from client: CMIOExtensionClient) {
        logger.info("Provider disconnect from \(describe(client: client), privacy: .public)")
        deviceSource.noteClientDisconnected()
    }

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
