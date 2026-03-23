import SwiftUI

struct CameraPreviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black

            if let previewImage = model.previewImage {
                Image(decorative: previewImage, scale: 1)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Waiting for camera frames...")
                        .foregroundStyle(.white.opacity(0.5))
                        .font(.title3)
                }
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
