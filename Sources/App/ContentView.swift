import AutoFrameCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                previewPane
                controlsPane
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 1100, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.onAppear()
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.title2.weight(.semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black)

                if let previewImage = model.previewImage {
                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(8)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Waiting for camera frames")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .frame(minWidth: 680, minHeight: 420)

            HStack(spacing: 12) {
                Button("Restart Preview") {
                    model.applySettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Stop Preview") {
                    model.stopPreview()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controlsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Controls")
                .font(.title2.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Source camera", selection: $model.selectedCameraID) {
                        ForEach(model.cameras) { camera in
                            Text(camera.label).tag(Optional(camera.uniqueID))
                        }
                    }
                    .onChange(of: model.selectedCameraID) { _ in
                        model.applySettings()
                    }

                    Picker("Output", selection: $model.selectedOutput) {
                        ForEach(OutputResolution.allCases) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    .onChange(of: model.selectedOutput) { _ in
                        model.applySettings()
                    }

                    Picker("Preset", selection: $model.selectedPreset) {
                        ForEach(FramingPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .onChange(of: model.selectedPreset) { _ in
                        model.applySettings()
                    }

                    Toggle("Tracking enabled", isOn: $model.trackingEnabled)
                        .onChange(of: model.trackingEnabled) { _ in
                            model.applySettings()
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Follow smoothness: \(model.smoothing, format: .number.precision(.fractionLength(2)))")
                        Slider(value: $model.smoothing, in: 0.45 ... 0.95, step: 0.01) {
                            Text("Follow smoothness")
                        }
                        .onChange(of: model.smoothing) { _ in
                            model.persistSettings()
                        }
                        Text("Higher values reduce jitter but add a bit of lag.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zoom strength: \(model.zoomLabel)")
                        Slider(value: $model.zoomStrength, in: 0 ... 1, step: 0.05) {
                            Text("Zoom strength")
                        }
                        .onChange(of: model.zoomStrength) { _ in
                            model.persistSettings()
                        }
                        Text("Controls how tightly AutoFrame crops around you.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text("Framing")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Install Virtual Camera") {
                        model.installExtension()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Uninstall Virtual Camera") {
                        model.uninstallExtension()
                    }
                    .buttonStyle(.bordered)

                    Text(model.extensionManager.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("System Extension")
            }

            Spacer()
        }
        .frame(width: 320, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("Input FPS \(model.stats.inputFPS, format: .number.precision(.fractionLength(1)))")
            Text("Output FPS \(model.stats.outputFPS, format: .number.precision(.fractionLength(1)))")
            Text("Face confidence \(model.stats.faceConfidence, format: .number.precision(.fractionLength(2)))")
            Text("Crop \(model.stats.cropCoverage * 100, format: .number.precision(.fractionLength(0)))%")
            Spacer()
            Text(model.statusMessage)
                .foregroundStyle(.secondary)
        }
        .font(.footnote.monospacedDigit())
        .padding(.horizontal, 8)
    }
}
