import AutoFrameCore
@preconcurrency import AVFoundation
import Foundation

final class PreviewStream: @unchecked Sendable {
    var onFrameEnqueued: (@Sendable (Double, CFAbsoluteTime) -> Void)?

    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private let queue = DispatchQueue(label: "dev.autoframe.preview.stream", qos: .userInteractive)
    private var fpsWindow: [CFAbsoluteTime] = []
    private var hasDeliveredFirstFrame = false
    private var lastMetricsReportTime: CFAbsoluteTime = .zero

    func attach(to displayLayer: AVSampleBufferDisplayLayer) {
        let displayLayerBox = DisplayLayerBox(displayLayer)
        queue.async { [weak self] in
            let displayLayer = displayLayerBox.layer
            guard let self else { return }
            guard self.displayLayer !== displayLayer else { return }
            self.displayLayer = displayLayer
            self.hasDeliveredFirstFrame = false
            self.lastMetricsReportTime = .zero
            displayLayer.flushAndRemoveImage()
        }
    }

    func detach(from displayLayer: AVSampleBufferDisplayLayer) {
        let displayLayerBox = DisplayLayerBox(displayLayer)
        queue.async { [weak self] in
            let displayLayer = displayLayerBox.layer
            if self?.displayLayer === displayLayer {
                self?.displayLayer = nil
            }
            displayLayer.flushAndRemoveImage()
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.fpsWindow.removeAll(keepingCapacity: true)
            self?.hasDeliveredFirstFrame = false
            self?.lastMetricsReportTime = .zero
            self?.displayLayer?.flushAndRemoveImage()
        }
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer) {
        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        guard let sampleBuffer = try? SampleBufferFactory.makeSampleBuffer(
            from: pixelBuffer,
            presentationTimeStamp: presentationTime
        ) else {
            return
        }

        let sampleBufferBox = SampleBufferBox(sampleBuffer)
        queue.async { [weak self] in
            guard let self, let displayLayer = self.displayLayer else { return }

            if displayLayer.status == .failed {
                displayLayer.flush()
            }

            guard displayLayer.isReadyForMoreMediaData else {
                return
            }

            displayLayer.enqueue(sampleBufferBox.sampleBuffer)

            let now = CFAbsoluteTimeGetCurrent()
            self.update(window: &self.fpsWindow, now: now)
            guard !self.hasDeliveredFirstFrame || now - self.lastMetricsReportTime >= 0.25 else {
                return
            }

            self.hasDeliveredFirstFrame = true
            self.lastMetricsReportTime = now
            self.onFrameEnqueued?(self.rollingFPS(from: self.fpsWindow), now)
        }
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

private final class DisplayLayerBox: @unchecked Sendable {
    let layer: AVSampleBufferDisplayLayer

    init(_ layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
    }
}

private final class SampleBufferBox: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(_ sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}
