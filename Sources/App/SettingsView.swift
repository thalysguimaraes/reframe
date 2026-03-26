import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // App identity
            VStack(spacing: 12) {
                if let iconImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "topbar-icon@2x", ofType: "png") ?? "") {
                    Image(nsImage: iconImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                }

                VStack(spacing: 4) {
                    Text("Reframe")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textHeading)

                    Text("Version 0.1.0")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                Text("by Thalys Guimarães")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            // Settings
            VStack(spacing: 0) {
                // Appearance
                settingsRow(icon: "moon.circle", label: "Dark mode") {
                    Toggle("", isOn: $model.isDarkMode)
                        .toggleStyle(ControlSurfaceToggleStyle())
                        .labelsHidden()
                        .onChange(of: model.isDarkMode) { _ in
                            model.persistSettings()
                        }
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                settingsRow(
                    icon: "menubar.rectangle",
                    label: "Show in menu bar",
                    subtitle: "Keep Reframe available from the macOS menu bar."
                ) {
                    Toggle("", isOn: $model.showInMenuBar)
                        .toggleStyle(ControlSurfaceToggleStyle())
                        .labelsHidden()
                        .onChange(of: model.showInMenuBar) { _ in
                            model.persistSettings()
                        }
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                settingsRow(
                    icon: "square.grid.2x2",
                    label: "Show Dock icon",
                    subtitle: model.dockIconSettingSubtitle
                ) {
                    Toggle("", isOn: $model.showDockIcon)
                        .toggleStyle(ControlSurfaceToggleStyle())
                        .labelsHidden()
                        .disabled(!model.showInMenuBar)
                        .onChange(of: model.showDockIcon) { _ in
                            model.persistSettings()
                        }
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                settingsRow(
                    icon: "rectangle.inset.filled.and.person.filled",
                    label: "Keep running on close",
                    subtitle: model.keepRunningSettingSubtitle
                ) {
                    Toggle("", isOn: $model.keepRunningOnClose)
                        .toggleStyle(ControlSurfaceToggleStyle())
                        .labelsHidden()
                        .disabled(!model.showInMenuBar)
                        .onChange(of: model.keepRunningOnClose) { _ in
                            model.persistSettings()
                        }
                }

                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)

                // Virtual Camera
                settingsRow(
                    icon: "web.camera",
                    label: "Virtual camera",
                    subtitle: model.extensionManager.statusMessage,
                    subtitleLineLimit: 3
                ) {
                    virtualCameraTrailingControls()
                }
            }
            .background(Theme.backgroundControl, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.controlBorder, lineWidth: 1)
            )

            Spacer()
        }
        .fontDesign(.rounded)
        .padding(.top, 44)
        .padding([.horizontal, .bottom], 24)
        .frame(width: 420, height: 560)
        .background(Theme.backgroundWindow)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        label: String,
        subtitle: String? = nil,
        subtitleLineLimit: Int = 2,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(subtitleLineLimit)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func virtualCameraTrailingControls() -> some View {
        switch model.extensionManager.requestState {
        case .installing:
            statusBadge(title: "Installing")
        case .reinstalling:
            statusBadge(title: "Reinstalling")
        case .uninstalling:
            statusBadge(title: "Removing", background: Theme.signalWarning)
        case .checking where !model.extensionManager.hasResolvedStatus:
            statusBadge(title: "Checking", background: Theme.backgroundControlSelected)
        case .idle, .checking:
            switch model.extensionManager.installationState {
            case .awaitingUserApproval:
                HStack(spacing: 8) {
                    statusBadge(title: "Approval", background: Theme.signalWarning)
                    settingsActionButton("Open Settings") {
                        model.openExtensionApprovalSettings()
                    }
                }
            case .installed:
                HStack(spacing: 8) {
                    installedCheckBadge()
                    settingsActionButton(
                        "Reinstall",
                        disabled: !model.extensionManager.canReinstallExtension
                    ) {
                        model.reinstallExtension()
                    }
                }
            case .installedDisabled:
                HStack(spacing: 8) {
                    statusBadge(title: "Disabled", background: Theme.signalWarning)
                    settingsActionButton("Enable in Settings") {
                        model.openExtensionApprovalSettings()
                    }
                }
            case .readyToInstall:
                settingsActionButton(
                    "Install",
                    prominent: true,
                    disabled: !model.extensionManager.canActivateExtension
                ) {
                    model.installExtension()
                }
            case .uninstalling:
                HStack(spacing: 8) {
                    statusBadge(title: "Replacing")
                    settingsActionButton(
                        "Reinstall",
                        disabled: !model.extensionManager.canReinstallExtension
                    ) {
                        model.reinstallExtension()
                    }
                }
            case .unknown:
                if model.extensionManager.hasResolvedStatus && model.extensionManager.canActivateExtension {
                    settingsActionButton("Install", prominent: true) {
                        model.installExtension()
                    }
                } else if model.extensionManager.hasResolvedStatus {
                    statusBadge(title: "Unavailable", background: Theme.signalWarning)
                } else {
                    statusBadge(title: "Checking", background: Theme.backgroundControlSelected)
                }
            }
        }
    }

    @ViewBuilder
    private func settingsActionButton(
        _ title: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(title, action: action)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.accent)
                .disabled(disabled)
        } else {
            Button(title, action: action)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(disabled)
        }
    }

    private func installedCheckBadge() -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20))
            .foregroundStyle(.white, Theme.accent)
    }

    private func statusBadge(title: String, background: Color = Theme.accent) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
    }
}
