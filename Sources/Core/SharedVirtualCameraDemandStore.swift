import Foundation
import notify

public struct VirtualCameraDemandSnapshot: Codable, Equatable, Sendable {
    public var activeConsumerCount: Int
    public var lastHeartbeatAt: Date
    public var lastUpdatedAt: Date

    public init(
        activeConsumerCount: Int = 0,
        lastHeartbeatAt: Date = .distantPast,
        lastUpdatedAt: Date = .distantPast
    ) {
        self.activeConsumerCount = max(0, activeConsumerCount)
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastUpdatedAt = lastUpdatedAt
    }

    public func hasActiveConsumers(
        now: Date = Date(),
        heartbeatTimeout: TimeInterval = 2.5
    ) -> Bool {
        activeConsumerCount > 0 && now.timeIntervalSince(lastHeartbeatAt) <= heartbeatTimeout
    }
}

public final class SharedVirtualCameraDemandStore: @unchecked Sendable {
    public static let shared = SharedVirtualCameraDemandStore()

    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileURL: URL
    private let notificationName: String
    private var stateToken: Int32 = 0
    private var lastHeartbeatPersistDate = Date.distantPast

    public init(
        fileURL: URL = SharedStorage.virtualCameraDemandURL,
        notificationName: String = "dev.autoframe.AutoFrameCam.virtual-camera-demand"
    ) {
        self.fileURL = fileURL
        self.notificationName = notificationName
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> VirtualCameraDemandSnapshot {
        lock.withLock {
            loadLocked()
        }
    }

    public func currentSnapshot() -> VirtualCameraDemandSnapshot {
        lock.withLock {
            loadCurrentSnapshotLocked()
        }
    }

    public func hasActiveConsumers(
        now: Date = Date(),
        heartbeatTimeout: TimeInterval = 2.5
    ) -> Bool {
        lock.withLock {
            loadCurrentSnapshotLocked().hasActiveConsumers(now: now, heartbeatTimeout: heartbeatTimeout)
        }
    }

    public func setActiveConsumerCount(_ count: Int, at time: Date = Date()) {
        lock.withLock {
            let snapshot = VirtualCameraDemandSnapshot(
                activeConsumerCount: count,
                lastHeartbeatAt: time,
                lastUpdatedAt: time
            )
            saveLocked(snapshot)
            lastHeartbeatPersistDate = time
        }
    }

    public func heartbeat(
        activeConsumerCount: Int,
        at time: Date = Date(),
        minimumInterval: TimeInterval = 1.0
    ) {
        guard activeConsumerCount > 0 else {
            setActiveConsumerCount(0, at: time)
            return
        }

        lock.withLock {
            var snapshot = loadLocked()
            let clampedCount = max(0, activeConsumerCount)
            let heartbeatAge = time.timeIntervalSince(lastHeartbeatPersistDate)

            guard heartbeatAge >= minimumInterval || snapshot.activeConsumerCount != clampedCount else {
                return
            }

            if snapshot.lastUpdatedAt == .distantPast {
                snapshot.lastUpdatedAt = time
            }

            snapshot.activeConsumerCount = clampedCount
            snapshot.lastHeartbeatAt = time
            saveLocked(snapshot)
            lastHeartbeatPersistDate = time
        }
    }

    public func clear(at time: Date = Date()) {
        setActiveConsumerCount(0, at: time)
    }

    @discardableResult
    public func observeChanges(
        queue: DispatchQueue = .main,
        handler: @escaping @Sendable (VirtualCameraDemandSnapshot) -> Void
    ) -> SharedVirtualCameraDemandObservation? {
        var token: Int32 = 0
        let status = notify_register_dispatch(notificationName, &token, queue) { [weak self] _ in
            guard let self else { return }
            handler(self.currentSnapshot())
        }

        guard status == NOTIFY_STATUS_OK else {
            return nil
        }

        return SharedVirtualCameraDemandObservation(token: token)
    }

    private func loadLocked() -> VirtualCameraDemandSnapshot {
        guard
            let data = try? Data(contentsOf: fileURL),
            let snapshot = try? decoder.decode(VirtualCameraDemandSnapshot.self, from: data)
        else {
            return .init()
        }

        return snapshot
    }

    private func loadCurrentSnapshotLocked() -> VirtualCameraDemandSnapshot {
        loadStateSnapshotLocked() ?? loadLocked()
    }

    private func loadStateSnapshotLocked() -> VirtualCameraDemandSnapshot? {
        guard let token = registeredStateTokenLocked() else {
            return nil
        }

        var packedState: UInt64 = 0
        guard notify_get_state(token, &packedState) == NOTIFY_STATUS_OK else {
            return nil
        }

        guard packedState != 0 else {
            return nil
        }

        let activeConsumerCount = Int((packedState >> 48) & 0xFFFF)
        let heartbeatMillis = packedState & 0x0000_FFFF_FFFF_FFFF
        let heartbeatAt = Date(timeIntervalSince1970: TimeInterval(heartbeatMillis) / 1000.0)
        return VirtualCameraDemandSnapshot(
            activeConsumerCount: activeConsumerCount,
            lastHeartbeatAt: heartbeatAt,
            lastUpdatedAt: heartbeatAt
        )
    }

    private func registeredStateTokenLocked() -> Int32? {
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

    private func saveLocked(_ snapshot: VirtualCameraDemandSnapshot) {
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }

        if let token = registeredStateTokenLocked() {
            notify_set_state(token, packedState(for: snapshot))
        }

        notify_post(notificationName)
    }

    private func packedState(for snapshot: VirtualCameraDemandSnapshot) -> UInt64 {
        guard snapshot.activeConsumerCount > 0 else {
            return 0
        }

        let clampedCount = UInt64(min(max(snapshot.activeConsumerCount, 0), 0xFFFF))
        let heartbeatMillis = UInt64(max(0, snapshot.lastHeartbeatAt.timeIntervalSince1970 * 1000.0))
        return (clampedCount << 48) | (heartbeatMillis & 0x0000_FFFF_FFFF_FFFF)
    }
}

public final class SharedVirtualCameraDemandObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var token: Int32?

    fileprivate init(token: Int32) {
        self.token = token
    }

    deinit {
        cancel()
    }

    public func cancel() {
        lock.withLock {
            guard let token else { return }
            notify_cancel(token)
            self.token = nil
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
