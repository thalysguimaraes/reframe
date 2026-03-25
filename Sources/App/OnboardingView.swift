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
            case .welcome: return "Welcome"
            case .cameraAccess: return "Camera"
            case .virtualCamera: return "Virtual Camera"
            case .ready: return "Ready"
            }
        }

        var headline: String {
            switch self {
            case .welcome: return "Smart framing for any webcam"
            case .cameraAccess: return "Give Reframe access to your camera"
            case .virtualCamera: return "Install the virtual camera"
            case .ready: return "You're ready to go"
            }
        }
    }

    @ObservedObject var model: AppModel
    @State private var currentStep: Step = .welcome

    private let stepAnimation = Animation.spring(response: 0.35, dampingFraction: 0.7)

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .cameraAccess:
                    cameraAccessStep
                case .virtualCamera:
                    virtualCameraStep
                case .ready:
                    readyStep
                }
            }
            .id(currentStep.id)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
            .animation(stepAnimation, value: currentStep)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let iconImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "topbar-icon@2x", ofType: "png") ?? "") {
                Image(nsImage: iconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Text("Reframe")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textHeading)

            Spacer()

            stepProgress
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var stepProgress: some View {
        let currentIndex = visibleSteps.firstIndex(of: currentStep) ?? 0

        return HStack(spacing: 5) {
            ForEach(Array(visibleSteps.enumerated()), id: \.element.id) { index, step in
                Capsule()
                    .fill(
                        step == currentStep ? Theme.accent :
                        index < currentIndex ? Theme.accent.opacity(0.4) :
                        Theme.textTertiary.opacity(0.25)
                    )
                    .frame(width: step == currentStep ? 22 : 6, height: 6)
                    .animation(stepAnimation, value: currentStep)
            }
        }
    }

    // MARK: - Step label + headline (shared across steps)

    private func stepHeader(step: Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.accent)

            Text(step.headline)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textHeading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(step: .welcome)

            Text("Reframe centers your shot in real time so Zoom, Meet, and every other video app sees a cleaner frame.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                OnboardingBullet(
                    icon: "person.crop.rectangle",
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

            VStack(alignment: .leading, spacing: 10) {
                if !model.extensionManager.hasResolvedStatus {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking setup…")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Button("Get started") {
                    moveToStep(nextRelevantStep(after: .welcome))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .disabled(!model.extensionManager.hasResolvedStatus)
            }
        }
    }

    // MARK: - Camera Access Step

    private var cameraAccessStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(step: .cameraAccess)

            Text(cameraPermissionDescription)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
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

            VStack(spacing: 10) {
                Button(cameraActionTitle) {
                    handleCameraPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)

                Button("Back") {
                    moveToStep(.welcome)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Virtual Camera Step

    private var virtualCameraStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(step: .virtualCamera)

            Text("Install the virtual camera so Zoom, Meet, FaceTime, and every other app can use your reframed feed.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
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

            VStack(spacing: 10) {
                Button(extensionPrimaryActionTitle) {
                    handleExtensionPrimaryAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .disabled(!canRunExtensionPrimaryAction)

                HStack(spacing: 10) {
                    Button("I'll do this later") {
                        moveToStep(.ready)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button("Back") {
                        moveToStep(previousRelevantStep(before: .virtualCamera))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Ready Step

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeader(step: .ready)

            Text("Your preview is live. Tight, Medium, and Wide change the framing, and Portrait mode softens the background.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
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
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.backgroundControl)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.controlBorder, lineWidth: 1)
                )

                if !requiresVirtualCameraStep {
                    OnboardingInlineStatus(message: "Virtual camera is ready, so other apps can pick Reframe immediately.")
                } else {
                    OnboardingInlineStatus(message: "You can keep working in the preview now and install the virtual camera later from the app.")
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button("Start using Reframe") {
                    model.completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)

                Button("Back") {
                    moveToStep(previousRelevantStep(before: .ready))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            model.startPreviewIfNeeded()
        }
    }

    // MARK: - Bindings

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

    // MARK: - Navigation helpers

    private var visibleSteps: [Step] {
        var steps: [Step] = [.welcome]
        if requiresCameraStep { steps.append(.cameraAccess) }
        if requiresVirtualCameraStep { steps.append(.virtualCamera) }
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
        case .authorized: return "Continue"
        case .notDetermined: return "Allow camera access"
        case .restricted, .denied: return "Open System Settings"
        @unknown default: return "Try again"
        }
    }

    private var extensionPrimaryActionTitle: String {
        switch model.extensionManager.installationState {
        case .installed: return "Continue"
        case .awaitingUserApproval, .installedDisabled: return "Open System Settings"
        case .uninstalling: return "Replace virtual camera"
        case .readyToInstall, .unknown: return "Install virtual camera"
        }
    }

    private var canRunExtensionPrimaryAction: Bool {
        switch model.extensionManager.installationState {
        case .installed: return true
        case .awaitingUserApproval, .installedDisabled: return true
        case .readyToInstall, .uninstalling: return model.extensionManager.canActivateExtension
        case .unknown: return model.extensionManager.canActivateExtension
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
        case .installed: moveToStep(.ready)
        case .awaitingUserApproval, .installedDisabled: model.openExtensionApprovalSettings()
        case .unknown, .readyToInstall, .uninstalling: model.installExtension()
        }
    }

    private func nextRelevantStep(after step: Step) -> Step {
        switch step {
        case .welcome:
            if requiresCameraStep { return .cameraAccess }
            if requiresVirtualCameraStep { return .virtualCamera }
            return .ready
        case .cameraAccess:
            if requiresVirtualCameraStep { return .virtualCamera }
            return .ready
        case .virtualCamera, .ready:
            return .ready
        }
    }

    private func previousRelevantStep(before step: Step) -> Step {
        switch step {
        case .welcome: return .welcome
        case .cameraAccess: return .welcome
        case .virtualCamera: return requiresCameraStep ? .cameraAccess : .welcome
        case .ready:
            if requiresVirtualCameraStep { return .virtualCamera }
            if requiresCameraStep { return .cameraAccess }
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
        withAnimation(stepAnimation) {
            currentStep = step
        }
    }
}

// MARK: - Subviews

private struct OnboardingBullet: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text(detail)
                    .font(.system(size: 12, design: .rounded))
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
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Text(detail)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.backgroundControl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}

private struct OnboardingInlineStatus: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)

            Text(message)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.backgroundControl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.controlBorder, lineWidth: 1)
        )
    }
}
