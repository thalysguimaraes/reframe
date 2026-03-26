import AutoFrameCore
import SwiftUI

struct ContentView: View {
    private static let topBarIconImage: NSImage? = {
        guard let path = Bundle.main.path(forResource: "topbar-icon@2x", ofType: "png") else {
            return nil
        }

        return NSImage(contentsOfFile: path)
    }()

    @ObservedObject var model: AppModel
    @State private var iconHovered = false
    @State private var isHoveringStatus = false

    var body: some View {
        Group {
            if model.showingOnboarding {
                OnboardingView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                mainContent
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .fontDesign(.rounded)
        .background(Theme.backgroundWindow)
        .preferredColorScheme(model.isDarkMode ? .dark : .light)
        .onAppear {
            model.onAppear()
        }
        .sheet(isPresented: $model.showingSettings) {
            AboutView(model: model)
        }
    }

    private var mainContent: some View {
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
                Text(AppConstants.marketingVersion)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            if let iconImage = Self.topBarIconImage {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .scaleEffect(iconHovered ? 1.12 : 1.0)
                    .rotationEffect(.degrees(iconHovered ? 8 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: iconHovered)
                    .onHover { hovering in
                        iconHovered = hovering
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
                .overlay {
                    FaceTrackingOverlay(faceRect: model.normalizedFaceRect, isTracking: model.trackingEnabled, isVisible: isHoveringStatus)
                }
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
                PreviewFeedbackOverlay(model: model)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .padding(.horizontal, Theme.previewPadding)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: model.pipelineActivity)
        .animation(.easeInOut(duration: 0.2), value: model.previewState)
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
                        .fill(model.previewStatusIndicatorColor)
                        .frame(width: 7, height: 7)

                    Text(model.statusMessage)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.textStatus)
                }
                .onHover { hovering in
                    isHoveringStatus = hovering
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

private struct PreviewFeedbackOverlay: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                .fill(Theme.backgroundSidebar)

            VStack(spacing: 18) {
                icon

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textHeading)

                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                if case .noSignal = model.previewState {
                    HStack(spacing: 10) {
                        Button(model.switchCameraButtonTitle) {
                            model.switchToSuggestedCamera()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Theme.accent)

                        if model.suggestedRecoveryCamera != nil {
                            Button("Retry") {
                                model.retrySelectedCamera()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                }
            }
            .padding(28)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch model.previewState {
        case .warmingUp:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.accent)

                Image(systemName: "video.badge.ellipsis")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        case .noSignal:
            ZStack {
                Circle()
                    .fill(Theme.signalWarning.opacity(0.15))
                    .frame(width: 78, height: 78)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.signalWarning)
            }
        case .idle, .live:
            Image(systemName: "video.fill")
                .font(.system(size: 48))
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
            return "Select a camera to start the live preview."
        }
    }

    private var borderColor: Color {
        if case .noSignal = model.previewState {
            return Theme.signalWarningBorder
        }
        return Theme.controlBorder
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

private struct FaceTrackingOverlay: View {
    let faceRect: CGRect?
    let isTracking: Bool
    let isVisible: Bool

    var body: some View {
        GeometryReader { geo in
            if isVisible, isTracking, let rect = faceRect {
                let frame = CGRect(
                    x: rect.minX * geo.size.width,
                    y: rect.minY * geo.size.height,
                    width: rect.width * geo.size.width,
                    height: rect.height * geo.size.height
                )
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.7), lineWidth: 1.5)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .animation(.easeOut(duration: 0.1), value: rect.origin.x)
                    .animation(.easeOut(duration: 0.1), value: rect.origin.y)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isVisible)
    }
}
