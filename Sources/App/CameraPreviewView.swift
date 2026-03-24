import AVFoundation
import AppKit
import SwiftUI

struct CameraPreviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black

            CameraPreviewSurfaceView(previewStream: model.previewStream)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !model.hasPreviewFrame {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Waiting for camera frames...")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.title3)
                }
            } else {
                EmptyView()
            }

            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        model.applySettings()
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        model.stopPreview()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 16)
            }
        }
        .padding(8)
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
    private let maskLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let rootLayer = CALayer()
        rootLayer.backgroundColor = NSColor.black.cgColor
        layer = rootLayer

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        rootLayer.addSublayer(displayLayer)
        rootLayer.mask = maskLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
        maskLayer.frame = bounds
        maskLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
    }
}
