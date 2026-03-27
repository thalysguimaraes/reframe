import AutoFrameCore
import XCTest

final class SharedVirtualCameraDemandStoreTests: XCTestCase {
    func testLoadReturnsEmptySnapshotWhenStoreDoesNotExist() throws {
        let store = try makeStore()

        let snapshot = store.load()

        XCTAssertEqual(snapshot.activeConsumerCount, 0)
        XCTAssertEqual(snapshot.lastHeartbeatAt, .distantPast)
        XCTAssertEqual(snapshot.lastUpdatedAt, .distantPast)
        XCTAssertFalse(snapshot.hasActiveConsumers())
    }

    func testSetActiveConsumerCountPersistsSnapshot() throws {
        let store = try makeStore()
        let timestamp = Date(timeIntervalSince1970: 123)

        store.setActiveConsumerCount(2, at: timestamp)

        let snapshot = store.load()
        XCTAssertEqual(snapshot.activeConsumerCount, 2)
        XCTAssertEqual(snapshot.lastHeartbeatAt, timestamp)
        XCTAssertEqual(snapshot.lastUpdatedAt, timestamp)
        XCTAssertTrue(snapshot.hasActiveConsumers(now: timestamp.addingTimeInterval(1.0)))
    }

    func testHeartbeatUpdatesLivenessWithoutChangingLastUpdatedAt() throws {
        let store = try makeStore()
        let startedAt = Date(timeIntervalSince1970: 100)
        let heartbeatAt = Date(timeIntervalSince1970: 101.5)

        store.setActiveConsumerCount(1, at: startedAt)
        store.heartbeat(activeConsumerCount: 1, at: heartbeatAt, minimumInterval: 0)

        let snapshot = store.load()
        XCTAssertEqual(snapshot.activeConsumerCount, 1)
        XCTAssertEqual(snapshot.lastUpdatedAt, startedAt)
        XCTAssertEqual(snapshot.lastHeartbeatAt, heartbeatAt)
    }

    func testSnapshotExpiresWhenHeartbeatGetsStale() {
        let heartbeatAt = Date(timeIntervalSince1970: 50)
        let snapshot = VirtualCameraDemandSnapshot(
            activeConsumerCount: 1,
            lastHeartbeatAt: heartbeatAt,
            lastUpdatedAt: heartbeatAt
        )

        XCTAssertTrue(snapshot.hasActiveConsumers(now: heartbeatAt.addingTimeInterval(2.0), heartbeatTimeout: 2.5))
        XCTAssertFalse(snapshot.hasActiveConsumers(now: heartbeatAt.addingTimeInterval(2.6), heartbeatTimeout: 2.5))
    }

    func testObserverReceivesDemandUpdates() throws {
        let store = try makeStore()
        let expectation = expectation(description: "observer receives update")
        let timestamp = Date(timeIntervalSince1970: 321)
        let snapshotBox = SnapshotBox()

        let observation = store.observeChanges(queue: .main) { snapshot in
            snapshotBox.set(snapshot)
            if snapshot.activeConsumerCount == 1 {
                expectation.fulfill()
            }
        }

        XCTAssertNotNil(observation)

        store.setActiveConsumerCount(1, at: timestamp)

        wait(for: [expectation], timeout: 2.0)
        let snapshot = snapshotBox.get()

        XCTAssertEqual(snapshot?.activeConsumerCount, 1)
        XCTAssertEqual(snapshot?.lastHeartbeatAt, timestamp)
        XCTAssertEqual(snapshot?.lastUpdatedAt, timestamp)
        observation?.cancel()
    }

    private func makeStore() throws -> SharedVirtualCameraDemandStore {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        return SharedVirtualCameraDemandStore(
            fileURL: directoryURL.appendingPathComponent("virtual-camera-demand.json"),
            notificationName: "test.virtual-camera-demand.\(UUID().uuidString)"
        )
    }
}

private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: VirtualCameraDemandSnapshot?

    func set(_ snapshot: VirtualCameraDemandSnapshot) {
        lock.lock()
        self.snapshot = snapshot
        lock.unlock()
    }

    func get() -> VirtualCameraDemandSnapshot? {
        lock.lock()
        let snapshot = snapshot
        lock.unlock()
        return snapshot
    }
}
