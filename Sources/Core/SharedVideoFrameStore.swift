import CoreImage
import CoreVideo
import Foundation
import IOSurface
import notify

public struct SharedVideoFrameDescriptor: Codable, Equatable, Sendable {
    public let height: Int
    public let pixelFormat: UInt32
    public let publishedAt: Date
    public let sequenceNumber: UInt64
    public let surfaceID: UInt32
    public let width: Int
}

public struct SharedVideoFrameSnapshot {
    public let descriptor: SharedVideoFrameDescriptor
    public let pixelBuffer: CVPixelBuffer
}

public final class SharedVideoFrameStore: @unchecked Sendable {
    public static let shared = SharedVideoFrameStore()

    private let lock = NSLock()
    private let renderContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    private let retainedBufferLimit = 6
    private let notificationName = "dev.autoframe.AutoFrameCam.latest-frame"

    private var nextSequenceNumber: UInt64 = 0
    private var stateToken: Int32 = 0
    private var observedPackedState: UInt64 = 0
    private var observedPackedStateDate = Date.distantPast
    private var publishedBufferPool: CVPixelBufferPool?
    private var publishedBufferSpec: PublishedBufferSpec?
    private var retainedBuffers: [CVPixelBuffer] = []

    public init() {}

    public func publish(_ pixelBuffer: CVPixelBuffer) {
        guard
            let shareableBuffer = makeShareableBuffer(from: pixelBuffer),
            let surface = CVPixelBufferGetIOSurface(shareableBuffer)?.takeUnretainedValue()
        else {
            return
        }

        let descriptor = lock.withLock {
            nextSequenceNumber += 1
            retainedBuffers.append(shareableBuffer)
            if retainedBuffers.count > retainedBufferLimit {
                retainedBuffers.removeFirst(retainedBuffers.count - retainedBufferLimit)
            }

            return SharedVideoFrameDescriptor(
                height: CVPixelBufferGetHeight(shareableBuffer),
                pixelFormat: CVPixelBufferGetPixelFormatType(shareableBuffer),
                publishedAt: Date(),
                sequenceNumber: nextSequenceNumber,
                surfaceID: IOSurfaceGetID(surface),
                width: CVPixelBufferGetWidth(shareableBuffer)
            )
        }

        guard let token = registeredStateToken() else { return }

        let packedState = pack(
            sequenceNumber: descriptor.sequenceNumber,
            surfaceID: descriptor.surfaceID
        )
        notify_set_state(token, packedState)
        notify_post(notificationName)
    }

    public func loadLatest(maximumAge: TimeInterval = 1.0) -> SharedVideoFrameSnapshot? {
        guard
            let token = registeredStateToken()
        else {
            return nil
        }

        var packedState: UInt64 = 0
        guard notify_get_state(token, &packedState) == NOTIFY_STATUS_OK else {
            return nil
        }

        guard
            packedState != 0,
            let surfaceID = unpackSurfaceID(from: packedState),
            let surface = IOSurfaceLookup(surfaceID)
        else {
            return nil
        }

        let now = Date()
        let frameAge = lock.withLock { () -> TimeInterval in
            if observedPackedState != packedState {
                observedPackedState = packedState
                observedPackedStateDate = now
            }
            return now.timeIntervalSince(observedPackedStateDate)
        }

        guard frameAge <= maximumAge else {
            return nil
        }

        let width = Int(IOSurfaceGetWidth(surface))
        let height = Int(IOSurfaceGetHeight(surface))
        let pixelFormat = IOSurfaceGetPixelFormat(surface)

        var unmanagedPixelBuffer: Unmanaged<CVPixelBuffer>?
        let attributes: [CFString: Any] = [
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width
        ]

        let status = CVPixelBufferCreateWithIOSurface(
            kCFAllocatorDefault,
            surface,
            attributes as CFDictionary,
            &unmanagedPixelBuffer
        )

        guard status == kCVReturnSuccess, let unmanagedPixelBuffer else {
            return nil
        }

        let pixelBuffer = unmanagedPixelBuffer.takeRetainedValue()
        let descriptor = SharedVideoFrameDescriptor(
            height: height,
            pixelFormat: pixelFormat,
            publishedAt: now,
            sequenceNumber: unpackSequenceNumber(from: packedState),
            surfaceID: surfaceID,
            width: width
        )
        return SharedVideoFrameSnapshot(descriptor: descriptor, pixelBuffer: pixelBuffer)
    }

    public func clear() {
        lock.withLock {
            observedPackedState = 0
            observedPackedStateDate = .distantPast
            retainedBuffers.removeAll(keepingCapacity: false)
        }

        guard let token = registeredStateToken() else { return }
        notify_set_state(token, 0)
        notify_post(notificationName)
    }

    private func registeredStateToken() -> Int32? {
        lock.withLock {
            if stateToken != 0 {
                return stateToken
            }

            var token: Int32 = 0
            guard notify_register_check(notificationName, &token) == NOTIFY_STATUS_OK else {
                return nil
            }

            stateToken = token
            return token
        }
    }

    private func pack(sequenceNumber: UInt64, surfaceID: UInt32) -> UInt64 {
        let truncatedSequence = sequenceNumber & 0xFFFF_FFFF
        return (truncatedSequence << 32) | UInt64(surfaceID)
    }

    private func unpackSurfaceID(from packedState: UInt64) -> UInt32? {
        let surfaceID = UInt32(packedState & 0xFFFF_FFFF)
        return surfaceID == 0 ? nil : surfaceID
    }

    private func unpackSequenceNumber(from packedState: UInt64) -> UInt64 {
        packedState >> 32
    }

    private func makeShareableBuffer(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue(), IOSurfaceGetID(surface) != 0 {
            return pixelBuffer
        }

        let spec = PublishedBufferSpec(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer)
        )

        let pool = lock.withLock { () -> CVPixelBufferPool? in
            if publishedBufferSpec != spec || publishedBufferPool == nil {
                publishedBufferSpec = spec
                publishedBufferPool = createPool(for: spec)
            }
            return publishedBufferPool
        }

        guard let pool else { return nil }

        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let outputBuffer else {
            return nil
        }

        renderContext.render(CIImage(cvPixelBuffer: pixelBuffer), to: outputBuffer)
        return outputBuffer
    }

    private func createPool(for spec: PublishedBufferSpec) -> CVPixelBufferPool? {
        let attributes: [NSString: Any] = [
            kCVPixelBufferWidthKey: spec.width,
            kCVPixelBufferHeightKey: spec.height,
            kCVPixelBufferPixelFormatTypeKey: Int(spec.pixelFormat),
            // The system extension runs in a different process, so the published frame must
            // live in a globally discoverable IOSurface.
            kCVPixelBufferIOSurfacePropertiesKey: [
                "IOSurfaceIsGlobal" as CFString: true
            ]
        ]

        var bufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &bufferPool)
        return bufferPool
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private struct PublishedBufferSpec: Equatable {
    let width: Int
    let height: Int
    let pixelFormat: OSType
}
