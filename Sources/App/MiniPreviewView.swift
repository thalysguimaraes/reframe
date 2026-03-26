import AutoFrameCore
import SwiftUI

struct MiniPreviewView: View {
    @ObservedObject var model: AppModel
    let onExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            previewCard

            VStack(alignment: .leading, spacing: 14) {
                header
                cameraSection
                quickToggles
                framingSection
                expandButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .preferredColorScheme(model.isDarkMode ? .dark : .light)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reframe Mini")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textHeading)

                Text(model.statusMessage)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.previewStatusIndicatorColor)
                    .frame(width: 8, height: 8)

                Text(model.previewFPS > 0 ? String(format: "%.0f fps", model.previewFPS) : "Standby")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.backgroundControl, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Theme.controlBorder, lineWidth: 1)
            )
        }
    }

    private var previewCard: some View {
        ZStack {
            CameraPreviewView(model: model)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

            if let activity = model.pipelineActivity {
                MiniPipelineOverlay(activity: activity)
            } else if !model.hasPreviewFrame {
                MiniPreviewFeedbackOverlay(model: model)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .background(Theme.backgroundSidebar)
        .clipped()
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniSectionLabel(title: "Camera")

            CameraDropdown(
                selection: $model.selectedCameraID,
                cameras: model.cameras,
                popoverWidth: 280
            ) {
                model.applyCameraSelection()
            }
            .disabled(model.isPipelineBusy || model.cameras.isEmpty)
        }
    }

    private var quickToggles: some View {
        HStack(spacing: 10) {
            MiniQuickToggle(
                title: "Portrait",
                icon: "person.and.background.dotted",
                isOn: $model.portraitModeEnabled
            ) {
                model.persistSettings()
            }

            MiniQuickToggle(
                title: "Tracking",
                icon: "scope",
                isOn: $model.trackingEnabled
            ) {
                model.persistSettings()
            }
        }
    }

    private var framingSection: some View {
        VStack(spacing: 8) {
            MiniSectionLabel(title: "Framing")
                .frame(maxWidth: .infinity, alignment: .center)

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

    private var expandButton: some View {
        HStack(spacing: 0) {
            Button(action: onExpand) {
                HStack(spacing: 4) {
                    Text("Open Full App")
                        .font(.system(size: 12, design: .rounded))
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MiniSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
    }
}

private struct MiniQuickToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)

                Spacer(minLength: 0)

                Toggle("", isOn: $isOn)
                    .toggleStyle(ControlSurfaceToggleStyle())
                    .labelsHidden()
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.backgroundControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
        .onChange(of: isOn) { _ in
            onChange()
        }
    }
}

private struct MiniPreviewFeedbackOverlay: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            icon

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textHeading)

                Text(subtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            if case .noSignal = model.previewState {
                Button("Retry") {
                    model.retrySelectedCamera()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundSidebar.opacity(0.95))
    }

    @ViewBuilder
    private var icon: some View {
        switch model.previewState {
        case .warmingUp:
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
        case .noSignal:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.signalWarning)
        case .idle, .live:
            Image(systemName: "video.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var title: String {
        switch model.previewState {
        case .warmingUp:
            return model.previewWarmupTitle
        case .noSignal:
            return model.previewNoSignalTitle
        case .idle, .live:
            return "Camera Preview"
        }
    }

    private var subtitle: String {
        switch model.previewState {
        case .warmingUp:
            return model.previewWarmupSubtitle
        case .noSignal:
            return model.previewNoSignalSubtitle
        case .idle, .live:
            return "Open the popover any time to check your framing."
        }
    }
}

private struct MiniPipelineOverlay: View {
    let activity: AppModel.PipelineActivity

    var body: some View {
        ZStack {
            Theme.previewOverlay

            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)

                VStack(spacing: 4) {
                    Text(activity.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.previewOverlayTextPrimary)

                    Text(activity.detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.previewOverlayTextSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(18)
        }
    }
}
