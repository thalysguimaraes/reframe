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
    let displayLayer = AVSampleBufferDisplayLayer()
    weak var previewStream: PreviewStream?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = CGColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        layer = rootLayer

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1)
        rootLayer.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }
}
