import Foundation

public struct PreviewSignalMonitor: Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case warmingUp
        case live
        case noSignal(NoSignalReason)
    }

    public enum NoSignalReason: Equatable, Sendable {
        case startupTimeout
        case interrupted
    }

    public let initialFrameTimeout: CFTimeInterval
    public let interruptedSignalTimeout: CFTimeInterval

    private var sessionStartTime: CFAbsoluteTime?
    private var lastFrameTime: CFAbsoluteTime?

    public init(
        initialFrameTimeout: CFTimeInterval = 4.0,
        interruptedSignalTimeout: CFTimeInterval = 2.5
    ) {
        self.initialFrameTimeout = initialFrameTimeout
        self.interruptedSignalTimeout = interruptedSignalTimeout
    }

    public var isActive: Bool {
        sessionStartTime != nil
    }

    public var hasReceivedFrame: Bool {
        lastFrameTime != nil
    }

    public mutating func begin(at time: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        sessionStartTime = time
        lastFrameTime = nil
    }

    public mutating func recordFrame(at time: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        if sessionStartTime == nil {
            sessionStartTime = time
        }

        lastFrameTime = time
    }

    public mutating func stop() {
        sessionStartTime = nil
        lastFrameTime = nil
    }

    public func state(at time: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> State {
        guard let sessionStartTime else {
            return .idle
        }

        guard let lastFrameTime else {
            return time - sessionStartTime >= initialFrameTimeout ? .noSignal(.startupTimeout) : .warmingUp
        }

        return time - lastFrameTime >= interruptedSignalTimeout ? .noSignal(.interrupted) : .live
    }
}
