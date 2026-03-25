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
            .disabled(model.isPipelineBusy)
            .onChange(of: model.selectedCameraID) { _ in
                model.applyCameraSelection()
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

            SegmentedControl(
                selection: $model.selectedOutput,
                options: OutputResolution.allCases,
                label: \.displayName
            )
            .disabled(model.isPipelineBusy)
            .onChange(of: model.selectedOutput) { _ in
                model.applyOutputSelection()
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

            SegmentedControl(
                selection: $model.selectedPreset,
                options: FramingPreset.allCases,
                label: \.displayName
            )
            .onChange(of: model.selectedPreset) { _ in
                model.persistSettings()
            }
        }
    }
}

// MARK: - Tracking

struct TrackingSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SidebarSectionHeader(title: "Tracking", icon: "person.crop.rectangle")
                Spacer()
                Toggle("", isOn: $model.trackingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .onChange(of: model.trackingEnabled) { _ in
                        model.persistSettings()
                    }
            }

            if model.trackingEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Smoothness")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(model.smoothing, format: .number.precision(.fractionLength(2)))")
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                    }
                    .font(.system(size: 12))

                    Slider(value: $model.smoothing, in: 0.45 ... 0.95, step: 0.01)
                        .tint(Theme.accent)
                        .onChange(of: model.smoothing) { _ in
                            model.persistSettings()
                        }

                    Text("Higher values reduce jitter but add lag.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: model.trackingEnabled)
    }
}

// MARK: - Zoom

struct ZoomSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SidebarSectionHeader(title: "Zoom", icon: "magnifyingglass")
                Spacer()
                Toggle("", isOn: $model.zoomEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .onChange(of: model.zoomEnabled) { newValue in
                        if !newValue {
                            model.zoomStrength = 0
                        } else if model.zoomStrength == 0 {
                            model.zoomStrength = 0.5
                        }
                        model.persistSettings()
                    }
            }

            if model.zoomEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Strength")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(model.zoomLabel)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(.system(size: 12))

                    Slider(value: $model.zoomStrength, in: 0.05 ... 1, step: 0.05)
                        .tint(Theme.accent)
                        .onChange(of: model.zoomStrength) { _ in
                            model.persistSettings()
                        }

                    Text("Controls how tightly the frame crops around you.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: model.zoomEnabled)
    }
}

// MARK: - Portrait

struct PortraitSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SidebarSectionHeader(title: "Portrait", icon: "person.and.background.dotted")
                Spacer()
                Toggle("", isOn: $model.portraitModeEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .onChange(of: model.portraitModeEnabled) { _ in
                        model.persistSettings()
                    }
            }

            if model.portraitModeEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Blur strength")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(model.portraitBlurLabel)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(.system(size: 12))

                    Slider(value: $model.portraitBlurStrength, in: 0 ... 1, step: 0.05)
                        .tint(Theme.accent)
                        .onChange(of: model.portraitBlurStrength) { _ in
                            model.persistSettings()
                        }

                    Text("Blurs the background while keeping you sharp.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: model.portraitModeEnabled)
    }
}

// MARK: - Custom Segmented Control

struct SegmentedControl<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    let label: KeyPath<T, String>
    @Namespace private var selectionNamespace
    @State private var hoveredOptionID: T.ID?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    segmentLabel(for: option)
                }
                .buttonStyle(SegmentedControlButtonStyle())
                .onHover { isHovering in
                    hoveredOptionID = isHovering ? option.id : nil
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.backgroundControl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.spring(response: 0.26, dampingFraction: 0.88), value: selection)
        .animation(.easeInOut(duration: 0.16), value: hoveredOptionID)
    }

    @ViewBuilder
    private func segmentLabel(for option: T) -> some View {
        let isSelected = selection == option
        let isHovered = hoveredOptionID == option.id

        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.backgroundControlSelected)
                    .shadow(color: Theme.controlShadow, radius: 10, y: 3)
                    .matchedGeometryEffect(id: "selected-segment", in: selectionNamespace)
            } else if isHovered && isEnabled {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.backgroundControlHover)
            }

            Text(option[keyPath: label])
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Theme.textPrimary : (isHovered ? Theme.textPrimary : Theme.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SegmentedControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Virtual Camera (used in SettingsView)

struct VirtualCameraSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Virtual Camera", icon: "web.camera")

            HStack(spacing: 8) {
                Button(model.extensionManager.primaryActionTitle) {
                    model.installExtension()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.accent)
                .disabled(!model.extensionManager.canActivateExtension)

                Button(model.extensionManager.secondaryActionTitle) {
                    model.uninstallExtension()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.extensionManager.canDeactivateExtension)
            }

            if !model.extensionManager.statusMessage.isEmpty {
                Text(model.extensionManager.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
