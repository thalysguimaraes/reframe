import AVFoundation
import AppKit
import SwiftUI

struct CameraPreviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        CameraPreviewSurfaceView(previewStream: model.previewStream)
    }
}

private struct CameraPreviewSurfaceView: NSViewRepresentable {
    let previewStream: PreviewStream

    func makeNSView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewStream = previewStream
        previewStream.attach(to: view.displayLayer)
        return view
    }

    func updateNSView(_ nsView: PreviewContainerView, context: Context) {
        nsView.previewStream = previewStream
        previewStream.attach(to: nsView.displayLayer)
    }

    static func dismantleNSView(_ nsView: PreviewContainerView, coordinator: ()) {
        nsView.previewStream?.detach(from: nsView.displayLayer)
        nsView.previewStream = nil
    }
}

private final class PreviewContainerView: NSView {
    private static let previewBackgroundColor = CGColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)

    let displayLayer = AVSampleBufferDisplayLayer()
    weak var previewStream: PreviewStream?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = Self.previewBackgroundColor
        rootLayer.cornerRadius = Theme.previewCornerRadius
        rootLayer.cornerCurve = .continuous
        rootLayer.masksToBounds = true
        layer = rootLayer

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = nil
        rootLayer.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerGeometry()
    }

    override func layout() {
        super.layout()
        updateLayerGeometry()
    }

    private func updateLayerGeometry() {
        guard let rootLayer = layer else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        rootLayer.contentsScale = scale
        displayLayer.contentsScale = scale
        displayLayer.frame = pixelAlignedFrame(for: bounds, scale: scale)
    }

    // Expand to backing-pixel boundaries so the display layer fully covers the clipped root layer.
    private func pixelAlignedFrame(for rect: CGRect, scale: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isEmpty else { return .zero }

        let minX = floor(rect.minX * scale) / scale
        let minY = floor(rect.minY * scale) / scale
        let maxX = ceil(rect.maxX * scale) / scale
        let maxY = ceil(rect.maxY * scale) / scale
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
