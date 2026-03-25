import SwiftUI

struct AboutView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Close button
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

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

                Divider().overlay(Theme.divider)

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

                Divider().overlay(Theme.divider)

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

                Divider().overlay(Theme.divider)

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

                Divider().overlay(Theme.divider)

                // Virtual Camera
                settingsRow(
                    icon: "web.camera",
                    label: "Virtual camera",
                    subtitle: model.extensionManager.statusMessage
                ) {
                    if model.extensionManager.isAwaitingUserApproval {
                        Button("Open Settings") {
                            model.openExtensionApprovalSettings()
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if model.extensionManager.isInstalled {
                        statusBadge(title: "Installed")
                    } else if model.extensionManager.canActivateExtension {
                        Button(model.extensionManager.primaryActionTitle) {
                            model.installExtension()
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Theme.accent)
                    } else {
                        statusBadge(title: "Unavailable")
                    }
                }

                Divider().overlay(Theme.divider)

                settingsRow(
                    icon: "sparkles.rectangle.stack",
                    label: "Onboarding",
                    subtitle: "Show the first-run setup flow again."
                ) {
                    Button("Reset") {
                        model.resetOnboarding()
                        dismiss()
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        .padding(24)
        .frame(width: 380, height: 560)
        .background(Theme.backgroundWindow)
    }

    private func settingsRow<Trailing: View>(
        icon: String,
        label: String,
        subtitle: String? = nil,
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
                        .lineLimit(2)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func statusBadge(title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.backgroundControlSelected, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}
