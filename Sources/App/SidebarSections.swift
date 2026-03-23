import AutoFrameCore
import SwiftUI

// MARK: - Camera

struct CameraSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Camera", icon: "video")

            Picker("Source", selection: $model.selectedCameraID) {
                ForEach(model.cameras) { camera in
                    Text(camera.label).tag(Optional(camera.uniqueID))
                }
            }
            .labelsHidden()
            .onChange(of: model.selectedCameraID) { _ in
                model.applySettings()
            }
        }
    }
}

// MARK: - Output

struct OutputSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Output", icon: "rectangle.on.rectangle")

            Picker("Output", selection: $model.selectedOutput) {
                ForEach(OutputResolution.allCases) { resolution in
                    Text(resolution.displayName).tag(resolution)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.selectedOutput) { _ in
                model.applySettings()
            }
        }
    }
}

// MARK: - Framing

struct FramingSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Framing", icon: "crop")

            Picker("Preset", selection: $model.selectedPreset) {
                ForEach(FramingPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: model.selectedPreset) { _ in
                model.applySettings()
            }
        }
    }
}

// MARK: - Tracking

struct TrackingSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Tracking", icon: "person.crop.rectangle")

            Toggle("Face tracking", isOn: $model.trackingEnabled)
                .toggleStyle(.switch)
                .onChange(of: model.trackingEnabled) { _ in
                    model.applySettings()
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Smoothness")
                    Spacer()
                    Text("\(model.smoothing, format: .number.precision(.fractionLength(2)))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.caption)

                Slider(value: $model.smoothing, in: 0.45 ... 0.95, step: 0.01)
                    .onChange(of: model.smoothing) { _ in
                        model.persistSettings()
                    }

                Text("Higher values reduce jitter but add lag.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .disabled(!model.trackingEnabled)
        }
    }
}

// MARK: - Zoom

struct ZoomSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Zoom", icon: "magnifyingglass")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text(model.zoomLabel)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Slider(value: $model.zoomStrength, in: 0 ... 1, step: 0.05)
                    .onChange(of: model.zoomStrength) { _ in
                        model.persistSettings()
                    }

                Text("Controls how tightly the frame crops around you.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Virtual Camera

struct VirtualCameraSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Virtual Camera", icon: "web.camera")

            HStack(spacing: 8) {
                Button("Install") {
                    model.installExtension()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Uninstall") {
                    model.uninstallExtension()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !model.extensionManager.statusMessage.isEmpty {
                Text(model.extensionManager.statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
