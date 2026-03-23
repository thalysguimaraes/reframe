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
    private let settingsStore = SharedSettingsStore.shared
    private let statsStore = SharedStatsStore.shared

    private var pipeline: AutoFramePipeline?
    private var activeStreamCount = 0

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
        activeStreamCount += 1
        guard pipeline == nil else { return }

        let pipeline = AutoFramePipeline(
            settingsProvider: { [weak self] in
                var settings = self?.settingsStore.load() ?? .default
                settings.outputResolution = outputResolution
                settings.cameraID = CameraCatalog.defaultPhysicalCameraID(preferredID: settings.cameraID)
                return settings
            },
            statsStore: statsStore
        )

        pipeline.onProcessedFrame = { [weak self] frame in
            self?.send(frame: frame)
        }

        do {
            try pipeline.start(cameraID: settingsStore.load().cameraID)
            self.pipeline = pipeline
            logger.info("Started virtual camera streaming.")
        } catch {
            logger.error("Failed to start virtual camera pipeline: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopStreaming() {
        activeStreamCount = max(0, activeStreamCount - 1)
        guard activeStreamCount == 0 else { return }

        pipeline?.stop()
        pipeline = nil
        logger.info("Stopped virtual camera streaming.")
    }

    private func send(frame: ProcessedFrame) {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard let sampleBuffer = try? SampleBufferFactory.makeSampleBuffer(
            from: frame.pixelBuffer,
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

