import AutoFrameCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var iconHovered = false

    var body: some View {
        HStack(spacing: 0) {
            if model.isSidebarVisible {
                SidebarView(model: model)
                    .transition(.move(edge: .leading))
            }

            VStack(spacing: 0) {
                topBar
                previewContainer
                statusBar
            }

            if model.isAdjustmentsSidebarVisible {
                AdjustmentsSidebarView(model: model)
                    .transition(.move(edge: .trailing))
            }
        }
        .fontDesign(.rounded)
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.backgroundWindow)
        .preferredColorScheme(model.isDarkMode ? .dark : .light)
        .onAppear {
            model.onAppear()
        }
        .sheet(isPresented: $model.showingSettings) {
            AboutView(model: model)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            if !model.isSidebarVisible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.isSidebarVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textLabel)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text("Reframe")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textHeading)
                Text("0.1.0")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            if let iconImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "topbar-icon@2x", ofType: "png") ?? "") {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .scaleEffect(iconHovered ? 1.12 : 1.0)
                    .rotationEffect(.degrees(iconHovered ? 8 : 0))
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            iconHovered = hovering
                        }
                    }
            }

            Spacer()

            Button {
                model.showingSettings = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)

            if !model.isAdjustmentsSidebarVisible {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.isAdjustmentsSidebarVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.previewPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Preview Container

    private var previewContainer: some View {
        ZStack {
            CameraPreviewView(model: model)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous))
                .padding(.horizontal, Theme.previewPadding)
                .padding(.vertical, 8)

            if let activity = model.pipelineActivity {
                PipelineActivityOverlay(activity: activity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .padding(.horizontal, Theme.previewPadding)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !model.hasPreviewFrame {
                RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                    .fill(Theme.backgroundSidebar)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .padding(.horizontal, Theme.previewPadding)
                    .padding(.vertical, 8)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Theme.textTertiary)
                            Text("Camera Preview")
                                .foregroundStyle(Theme.textTertiary)
                                .font(.system(size: 13, design: .rounded))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: model.pipelineActivity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 0) {
            if model.showsDetailedStats {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 16) {
                        statItem("Capture", String(format: "%.1f", model.stats.captureFPS))
                        statItem("Process", String(format: "%.1f", model.stats.processingFPS))
                        statItem("Preview", String(format: "%.1f", model.previewFPS))
                        statItem("Relay", String(format: "%.1f", model.stats.relayFPS))
                        statItem("Face", String(format: "%.2f", model.stats.faceConfidence))
                        statItem("Crop", String(format: "%.0f%%", model.stats.cropCoverage * 100))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    Spacer()
                }
                .padding(.horizontal, Theme.previewPadding)
                .padding(.top, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(model.hasPreviewFrame ? Color.green : Theme.textTertiary)
                        .frame(width: 7, height: 7)

                    Text(model.statusMessage)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textStatus)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.showsDetailedStats.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Stats")
                            .font(.system(size: 11, design: .rounded))
                        Image(systemName: model.showsDetailedStats ? "chevron.down" : "chevron.up")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.previewPadding)
            .padding(.vertical, 12)
        }
        .animation(.easeInOut(duration: 0.2), value: model.showsDetailedStats)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct PipelineActivityOverlay: View {
    let activity: AppModel.PipelineActivity

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                .fill(Theme.previewOverlay)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)

                VStack(spacing: 4) {
                    Text(activity.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.previewOverlayTextPrimary)
                        .shadow(color: Theme.previewOverlayTextShadow, radius: 8, x: 0, y: 1)

                    Text(activity.detail)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.previewOverlayTextSecondary)
                        .shadow(color: Theme.previewOverlayTextShadow, radius: 6, x: 0, y: 1)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                .strokeBorder(Theme.previewOverlayStroke, lineWidth: 1)
        )
    }
}
