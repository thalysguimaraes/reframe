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
                }

                Divider().overlay(Theme.divider)

                // Virtual Camera
                settingsRow(
                    icon: "web.camera",
                    label: "Virtual camera",
                    subtitle: model.extensionManager.statusMessage
                ) {
                    if model.extensionManager.canActivateExtension {
                        Button(model.extensionManager.primaryActionTitle) {
                            model.installExtension()
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Theme.accent)
                    } else {
                        installedBadge
                    }
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
        .frame(width: 360, height: 400)
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
                        .lineLimit(1)
                }
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var installedBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 6, height: 6)

            Text("Installed")
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
