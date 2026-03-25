import AutoFrameCore
import AVFoundation
import AppKit
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case cameraAccess
        case virtualCamera
        case ready

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:
                return "Welcome"
            case .cameraAccess:
                return "Camera"
            case .virtualCamera:
                return "Virtual Camera"
            case .ready:
                return "Ready"
            }
        }

        var headline: String {
            switch self {
            case .welcome:
                return "Smart framing for any webcam"
            case .cameraAccess:
                return "Give Reframe access to your camera"
            case .virtualCamera:
                return "Install the virtual camera"
            case .ready:
                return "You are ready to start using Reframe"
            }
        }
    }

    @ObservedObject var model: AppModel
    @State private var currentStep: Step = .welcome

    private let transitionAnimation = Animation.spring(response: 0.35, dampingFraction: 0.6)

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 24) {
                contentCard
                    .frame(maxWidth: 400)

                visualCard
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.backgroundWindow)
        .onAppear {
            model.refreshOnboardingPrerequisites()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshOnboardingPrerequisites()
            reconcileCurrentStep()
        }
        .onChange(of: model.cameraAuthorizationStatus) { _ in
            if currentStep == .cameraAccess, !requiresCameraStep {
                moveToStep(nextRelevantStep(after: .cameraAccess))
            }
        }
        .onChange(of: model.extensionManager.installationState) { _ in
            if currentStep == .virtualCamera, !requiresVirtualCameraStep {
                moveToStep(.ready)
            }
        }
    }

    private var header: some View {
        let currentIndex = visibleSteps.firstIndex(of: currentStep) ?? 0

        return HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    if let iconImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "topbar-icon@2x", ofType: "png") ?? "") {
                        Image(nsImage: iconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reframe")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textHeading)

                        Text("First-run setup")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Text("A quick setup to get from install to a working preview without guesswork.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            HStack(spacing: 10) {
                ForEach(Array(visibleSteps.enumerated()), id: \.element.id) { index, step in
                    OnboardingStepPill(
                        title: step.title,
                        isCurrent: step == currentStep,
                        isComplete: index < currentIndex
                    )
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    private var contentCard: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 20) {
                Text(currentStep.title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)

                Text(currentStep.headline)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textHeading)
                    .fixedSize(horizontal: false, vertical: true)

                Group {
                    switch currentStep {
                    case .welcome:
                        welcomeCopy
                    case .cameraAccess:
                        cameraAccessCopy
                    case .virtualCamera:
                        virtualCameraCopy
                    case .ready:
                        readyCopy
                    }
                }
                .id(currentStep.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var visualCard: some View {
        switch currentStep {
        case .welcome:
            welcomeVisual
        case .cameraAccess:
            previewVisual(
                title: requiresCameraStep ? "Camera preview starts here" : "Preview is already live",
                caption: requiresCameraStep
                    ? "Grant camera access to see your reframed shot and keep configuration local to your Mac."
                    : "Reframe already has camera access, so you can continue straight to the live preview."
            )
        case .virtualCamera:
            extensionVisual
        case .ready:
            readyVisual
        }
    }

    private var welcomeCopy: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reframe centers your shot in real time so Zoom, Meet, and every other video app sees a cleaner frame.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                OnboardingBullet(
                    icon: "person.crop.rectangle.badge.checkmark",
                    title: "Automatic framing",
                    detail: "Keeps your face composed with natural headroom instead of a static wide shot."
                )
                OnboardingBullet(
                    icon: "video.badge.waveform",
                    title: "Works with your existing apps",
                    detail: "The virtual camera makes the improved feed available anywhere you pick a camera."
                )
                OnboardingBullet(
                    icon: "lock.shield",
                    title: "On-device processing",
                    detail: "Face detection and reframing stay on your Mac."
                )
            }

            Spacer(minLength: 0)

            if !model.extensionManager.hasResolvedStatus {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking your current camera extension status…")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 12) {
                Button("Get started") {
                    moveToStep(nextRelevantStep(after: .welcome))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(!model.extensionManager.hasResolvedStatus)
            }
        }
    }

    private var cameraAccessCopy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(cameraPermissionDescription)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                OnboardingCallout(
                    title: "Why Reframe needs camera access",
                    detail: "The app reads frames from your selected webcam so it can detect your face and reframe the shot in real time."
                )

                if model.cameraAuthorizationStatus == .denied || model.cameraAuthorizationStatus == .restricted {
                    OnboardingCallout(
                        title: "Recovery path",
                        detail: "Open System Settings > Privacy & Security > Camera and re-enable Reframe, then come back here."
                    )
                }
            }

            Spacer(minLength: 0)

            actionRow(
                primaryTitle: cameraActionTitle,
                primaryRole: nil,
                primaryAction: handleCameraPrimaryAction,
                secondaryTitle: currentStep == .cameraAccess ? "Back" : nil,
                secondaryAction: { moveToStep(.welcome) }
            )
        }
    }

    private var virtualCameraCopy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Install the virtual camera so Zoom, Meet, FaceTime, and every other app can use your reframed feed.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                OnboardingCallout(
                    title: "What happens next",
                    detail: "Reframe asks macOS to activate its camera extension. If approval is required, you will finish it in System Settings."
                )

                OnboardingCallout(
                    title: "Approval path",
                    detail: "System Settings > General > Login Items & Extensions > Camera Extensions"
                )

                if !model.extensionManager.statusMessage.isEmpty {
                    OnboardingInlineStatus(message: model.extensionManager.statusMessage)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(extensionPrimaryActionTitle) {
                    handleExtensionPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(!canRunExtensionPrimaryAction)

                Button("I'll do this later") {
                    moveToStep(.ready)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button("Back") {
                    moveToStep(previousRelevantStep(before: .virtualCamera))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var readyCopy: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your preview is live. Tight, Medium, and Wide change the framing, and Portrait mode softens the background.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Framing mode")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)

                    SegmentedControl(
                        selection: presetBinding,
                        options: FramingPreset.allCases,
                        label: \.displayName
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Portrait mode")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Blur the background while keeping you sharp.")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: portraitModeBinding)
                            .toggleStyle(ControlSurfaceToggleStyle())
                            .labelsHidden()
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.backgroundControl)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.controlBorder, lineWidth: 1)
                )
            }

            if !requiresVirtualCameraStep {
                OnboardingInlineStatus(message: "Virtual camera is ready, so other apps can pick Reframe immediately.")
            } else {
                OnboardingInlineStatus(message: "You can keep working in the preview now and install the virtual camera later from the app.")
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Start using Reframe") {
                    model.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)

                Button("Back") {
                    moveToStep(previousRelevantStep(before: .ready))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .onAppear {
            model.startPreviewIfNeeded()
        }
    }

    private var welcomeVisual: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    framingComparisonCard(
                        title: "Before",
                        subtitle: "Static wide shot",
                        accentOpacity: 0.18,
                        lineColor: Theme.textTertiary.opacity(0.55),
                        faceOffset: CGSize(width: -34, height: 0),
                        cropInset: 44
                    )

                    framingComparisonCard(
                        title: "After",
                        subtitle: "Centered and cropped",
                        accentOpacity: 0.32,
                        lineColor: Theme.accent.opacity(0.7),
                        faceOffset: CGSize(width: 0, height: -6),
                        cropInset: 24
                    )
                }

                HStack(spacing: 10) {
                    OnboardingTag(title: "Tight / Medium / Wide")
                    OnboardingTag(title: "Portrait mode")
                    OnboardingTag(title: "Works with Zoom")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func previewVisual(title: String, caption: String) -> some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textHeading)

                Text(caption)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)

                onboardingPreviewPanel(
                    overlayTitle: requiresCameraStep ? "Camera access needed" : nil,
                    overlayDetail: requiresCameraStep ? "Grant access to turn the preview on." : nil
                )
            }
        }
    }

    private var extensionVisual: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Reframe feed handoff")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textHeading)

                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        extensionNode(icon: "camera.fill", title: "Webcam")

                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)

                        extensionNode(icon: "sparkles.rectangle.stack", title: "Reframe")

                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)

                        extensionNode(icon: "video.badge.waveform", title: "Zoom / Meet")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        statusRow(
                            title: "Camera preview",
                            value: model.cameraAuthorizationStatus == .authorized ? "Ready" : "Waiting"
                        )
                        statusRow(
                            title: "Virtual camera",
                            value: extensionStatusLabel
                        )
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.backgroundControl)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.controlBorder, lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var readyVisual: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Live preview")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textHeading)

                    Spacer()

                    OnboardingTag(title: model.selectedPreset.displayName)
                }

                onboardingPreviewPanel(overlayTitle: nil, overlayDetail: nil)

                HStack(spacing: 10) {
                    OnboardingTag(title: "Tracking on")
                    if model.portraitModeEnabled {
                        OnboardingTag(title: "Portrait enabled")
                    }
                    OnboardingTag(title: "Ready for meetings")
                }
            }
        }
    }

    private func framingComparisonCard(
        title: String,
        subtitle: String,
        accentOpacity: Double,
        lineColor: Color,
        faceOffset: CGSize,
        cropInset: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.backgroundControl)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(lineColor, style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                    .padding(cropInset)

                Circle()
                    .fill(Theme.accent.opacity(accentOpacity))
                    .frame(width: 86, height: 86)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.white.opacity(0.88))
                    )
                    .offset(faceOffset)
            }
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.controlBorder, lineWidth: 1)
            )

            Text(subtitle)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func extensionNode(icon: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(Theme.backgroundControlSelected)
                )

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func onboardingPreviewPanel(overlayTitle: String?, overlayDetail: String?) -> some View {
        ZStack {
            CameraPreviewView(model: model)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous))

            if let activity = model.pipelineActivity {
                OnboardingPreviewActivityOverlay(activity: activity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if !model.hasPreviewFrame {
                RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                    .fill(Theme.backgroundSidebar)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: overlayTitle == nil ? "video.fill" : "video.badge.lock")
                                .font(.system(size: 42))
                                .foregroundStyle(Theme.textTertiary)

                            if let overlayTitle {
                                Text(overlayTitle)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                            } else {
                                Text("Waiting for first frame")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.textPrimary)
                            }

                            Text(overlayDetail ?? "Reframe will show the live preview here as soon as the camera session is ready.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                        }
                        .padding(28)
                    }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.previewCornerRadius, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: model.pipelineActivity)
    }

    private func actionRow(
        primaryTitle: String,
        primaryRole: ButtonRole?,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(primaryTitle, role: primaryRole, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)

            if let secondaryTitle {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }

    private var presetBinding: Binding<FramingPreset> {
        Binding(
            get: { model.selectedPreset },
            set: { newValue in
                model.selectedPreset = newValue
                model.persistSettings()
            }
        )
    }

    private var portraitModeBinding: Binding<Bool> {
        Binding(
            get: { model.portraitModeEnabled },
            set: { newValue in
                model.portraitModeEnabled = newValue
                model.persistSettings()
            }
        )
    }

    private var visibleSteps: [Step] {
        var steps: [Step] = [.welcome]

        if requiresCameraStep {
            steps.append(.cameraAccess)
        }

        if requiresVirtualCameraStep {
            steps.append(.virtualCamera)
        }

        steps.append(.ready)
        return steps
    }

    private var requiresCameraStep: Bool {
        model.cameraAuthorizationStatus != .authorized
    }

    private var requiresVirtualCameraStep: Bool {
        !model.extensionManager.isInstalled
    }

    private var cameraPermissionDescription: String {
        switch model.cameraAuthorizationStatus {
        case .authorized:
            return "Camera access is already granted. Reframe has started the live preview, so you can continue."
        case .notDetermined:
            return "Reframe needs your camera to detect your face and reframe the shot in real time before it can show a preview."
        case .restricted:
            return "Camera access is restricted on this Mac. Reframe cannot start the preview until the restriction is removed."
        case .denied:
            return "Camera access is currently denied. Re-enable Reframe in System Settings to continue the setup."
        @unknown default:
            return "Reframe needs camera access before it can start the live preview."
        }
    }

    private var cameraActionTitle: String {
        switch model.cameraAuthorizationStatus {
        case .authorized:
            return "Continue"
        case .notDetermined:
            return "Allow camera access"
        case .restricted, .denied:
            return "Open System Settings"
        @unknown default:
            return "Try again"
        }
    }

    private var extensionPrimaryActionTitle: String {
        switch model.extensionManager.installationState {
        case .installed:
            return "Continue"
        case .awaitingUserApproval, .installedDisabled:
            return "Open System Settings"
        case .uninstalling:
            return "Replace virtual camera"
        case .readyToInstall, .unknown:
            return "Install virtual camera"
        }
    }

    private var canRunExtensionPrimaryAction: Bool {
        switch model.extensionManager.installationState {
        case .installed:
            return true
        case .awaitingUserApproval, .installedDisabled:
            return true
        case .readyToInstall, .uninstalling:
            return model.extensionManager.canActivateExtension
        case .unknown:
            return model.extensionManager.canActivateExtension
        }
    }

    private var extensionStatusLabel: String {
        switch model.extensionManager.installationState {
        case .installed:
            return "Installed"
        case .awaitingUserApproval:
            return "Awaiting approval"
        case .installedDisabled:
            return "Installed but disabled"
        case .uninstalling:
            return "Replacing"
        case .readyToInstall:
            return "Not installed"
        case .unknown:
            return model.extensionManager.hasResolvedStatus ? "Needs attention" : "Checking"
        }
    }

    private func handleCameraPrimaryAction() {
        switch model.cameraAuthorizationStatus {
        case .authorized:
            moveToStep(nextRelevantStep(after: .cameraAccess))
        case .notDetermined:
            model.requestCameraAccessFromOnboarding()
        case .restricted, .denied:
            model.openCameraPrivacySettings()
        @unknown default:
            model.requestCameraAccessFromOnboarding()
        }
    }

    private func handleExtensionPrimaryAction() {
        switch model.extensionManager.installationState {
        case .installed:
            moveToStep(.ready)
        case .awaitingUserApproval, .installedDisabled:
            model.openExtensionApprovalSettings()
        case .unknown, .readyToInstall, .uninstalling:
            model.installExtension()
        }
    }

    private func nextRelevantStep(after step: Step) -> Step {
        switch step {
        case .welcome:
            if requiresCameraStep {
                return .cameraAccess
            }

            if requiresVirtualCameraStep {
                return .virtualCamera
            }

            return .ready
        case .cameraAccess:
            if requiresVirtualCameraStep {
                return .virtualCamera
            }

            return .ready
        case .virtualCamera, .ready:
            return .ready
        }
    }

    private func previousRelevantStep(before step: Step) -> Step {
        switch step {
        case .welcome:
            return .welcome
        case .cameraAccess:
            return .welcome
        case .virtualCamera:
            return requiresCameraStep ? .cameraAccess : .welcome
        case .ready:
            if requiresVirtualCameraStep {
                return .virtualCamera
            }

            if requiresCameraStep {
                return .cameraAccess
            }

            return .welcome
        }
    }

    private func reconcileCurrentStep() {
        switch currentStep {
        case .cameraAccess where !requiresCameraStep:
            moveToStep(nextRelevantStep(after: .cameraAccess))
        case .virtualCamera where !requiresVirtualCameraStep:
            moveToStep(.ready)
        default:
            break
        }
    }

    private func moveToStep(_ step: Step) {
        withAnimation(transitionAnimation) {
            currentStep = step
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack {
            content
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Theme.backgroundSidebar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}

private struct OnboardingBullet: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingCallout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.backgroundControl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}

private struct OnboardingInlineStatus: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)

            Text(message)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.backgroundControl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}

private struct OnboardingTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Theme.backgroundControl)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.controlBorder, lineWidth: 1)
            )
    }
}

private struct OnboardingStepPill: View {
    let title: String
    let isCurrent: Bool
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCurrent || isComplete ? Theme.accent : Theme.textTertiary)

            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(isCurrent ? Theme.backgroundControlSelected : Theme.backgroundControl)
        )
        .overlay(
            Capsule()
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}

private struct OnboardingPreviewActivityOverlay: View {
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
