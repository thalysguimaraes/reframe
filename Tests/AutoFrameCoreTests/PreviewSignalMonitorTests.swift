import AutoFrameCore
import XCTest

final class PreviewSignalMonitorTests: XCTestCase {
    func testStartsInWarmupBeforeFirstFrameTimeout() {
        var monitor = PreviewSignalMonitor(initialFrameTimeout: 4.0, interruptedSignalTimeout: 2.5)

        monitor.begin(at: 10.0)

        XCTAssertEqual(monitor.state(at: 13.9), .warmingUp)
    }

    func testTransitionsToStartupTimeoutWhenFirstFrameNeverArrives() {
        var monitor = PreviewSignalMonitor(initialFrameTimeout: 4.0, interruptedSignalTimeout: 2.5)

        monitor.begin(at: 10.0)

        XCTAssertEqual(monitor.state(at: 14.1), .noSignal(.startupTimeout))
    }

    func testTransitionsToInterruptedWhenFramesStopAfterStreaming() {
        var monitor = PreviewSignalMonitor(initialFrameTimeout: 4.0, interruptedSignalTimeout: 2.5)

        monitor.begin(at: 10.0)
        monitor.recordFrame(at: 11.0)

        XCTAssertEqual(monitor.state(at: 13.4), .live)
        XCTAssertEqual(monitor.state(at: 13.6), .noSignal(.interrupted))
    }

    func testRecoversWhenFramesResumeAfterInterruptedSignal() {
        var monitor = PreviewSignalMonitor(initialFrameTimeout: 4.0, interruptedSignalTimeout: 2.5)

        monitor.begin(at: 10.0)
        monitor.recordFrame(at: 11.0)
        XCTAssertEqual(monitor.state(at: 13.7), .noSignal(.interrupted))

        monitor.recordFrame(at: 13.8)

        XCTAssertEqual(monitor.state(at: 14.0), .live)
    }
}
