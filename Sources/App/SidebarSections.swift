import AutoFrameCore
import AppKit
import SwiftUI

// MARK: - Camera

struct CameraSectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarSectionHeader(title: "Camera", icon: "video")

            CameraDropdown(
                selection: $model.selectedCameraID,
                cameras: model.cameras
            ) {
                model.applyCameraSelection()
            }
            .disabled(model.isPipelineBusy || model.cameras.isEmpty)
        }
    }
}

struct CameraDropdown: View {
    @Binding var selection: String?
    let cameras: [CameraDeviceDescriptor]
    let onSelection: () -> Void

    @State private var isPresented = false
    @State private var hoveredCameraID: String?
    @State private var hoveredTrigger = false
    @State private var keyboardSelectionID: String?
    @FocusState private var focusedCameraID: String?
    @Environment(\.isEnabled) private var isEnabled

    private let popoverWidth: CGFloat
    private let popoverMaxHeight: CGFloat

    init(
        selection: Binding<String?>,
        cameras: [CameraDeviceDescriptor],
        popoverWidth: CGFloat = Theme.sidebarWidth - (Theme.sidebarPadding * 2),
        popoverMaxHeight: CGFloat = 248,
        onSelection: @escaping () -> Void
    ) {
        _selection = selection
        self.cameras = cameras
        self.onSelection = onSelection
        self.popoverWidth = popoverWidth
        self.popoverMaxHeight = popoverMaxHeight
    }

    private var selectedCamera: CameraDeviceDescriptor? {
        cameras.first(where: { $0.uniqueID == selection })
    }

    private var buttonTitle: String {
        selectedCamera?.localizedName ?? "No camera detected"
    }

    private var buttonSubtitle: String {
        selectedCamera?.detailsText ?? "Connect a webcam to continue."
    }

    var body: some View {
        Button {
            toggleDropdown()
        } label: {
            triggerLabel
        }
        .buttonStyle(SegmentedControlButtonStyle())
        .onHover { isHovering in
            hoveredTrigger = isHovering
        }
        .onMoveCommand { direction in
            guard isEnabled else { return }
            switch direction {
            case .down:
                presentDropdown(preferredSelection: selection ?? cameras.first?.uniqueID)
            case .up:
                presentDropdown(preferredSelection: selection ?? cameras.last?.uniqueID)
            default:
                break
            }
        }
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            popoverContent
        }
        .onChange(of: selection) { newValue in
            keyboardSelectionID = newValue
        }
        .onChange(of: cameras.map(\.uniqueID)) { _ in
            if let selection, !cameras.contains(where: { $0.uniqueID == selection }) {
                keyboardSelectionID = cameras.first?.uniqueID
            }
        }
        .onChange(of: isEnabled) { enabled in
            if !enabled {
                dismissDropdown()
            }
        }
        .accessibilityLabel("Camera source")
        .accessibilityValue(selectedCamera?.label ?? "No camera selected")
        .accessibilityHint(cameras.isEmpty ? "No cameras are currently available." : "Opens the camera selector.")
    }

    private var triggerLabel: some View {
        let isActive = isPresented || hoveredTrigger

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(buttonTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(buttonSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? Theme.textSecondary : Theme.textTertiary)
                .rotationEffect(.degrees(isPresented ? 180 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive && isEnabled ? Theme.backgroundControlSelected : Theme.backgroundControl)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isPresented ? Theme.accent.opacity(0.3) : Theme.controlBorder, lineWidth: 1)
        )
        .shadow(color: isPresented ? Theme.controlShadow.opacity(0.7) : .clear, radius: 12, y: 4)
        .opacity(isEnabled ? 1 : 0.55)
        .animation(.spring(response: 0.24, dampingFraction: 0.88), value: isPresented)
        .animation(.easeInOut(duration: 0.16), value: hoveredTrigger)
    }

    private var popoverContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: cameras.count > 4) {
                LazyVStack(spacing: 4) {
                    ForEach(cameras) { camera in
                        Button {
                            choose(camera)
                        } label: {
                            cameraRow(for: camera)
                        }
                        .buttonStyle(.plain)
                        .focusable()
                        .focused($focusedCameraID, equals: camera.uniqueID)
                        .cameraDropdownFocusEffectDisabled()
                        .id(camera.uniqueID)
                        .onHover { isHovering in
                            hoveredCameraID = isHovering ? camera.uniqueID : nil
                            if isHovering {
                                keyboardSelectionID = camera.uniqueID
                            }
                        }
                        .accessibilityLabel(camera.localizedName)
                        .accessibilityValue(camera.detailsText)
                        .accessibilityHint(selection == camera.uniqueID ? "Selected camera." : "Select camera.")
                        .accessibilityAddTraits(selection == camera.uniqueID ? .isSelected : [])
                    }
                }
                .padding(6)
            }
            .frame(width: popoverWidth)
            .frame(maxHeight: popoverMaxHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.backgroundSidebar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.controlBorder, lineWidth: 1)
            )
            .shadow(color: Theme.controlShadow.opacity(0.85), radius: 14, y: 6)
            .onAppear {
                keyboardSelectionID = keyboardSelectionID ?? selection ?? cameras.first?.uniqueID
                DispatchQueue.main.async {
                    focusedCameraID = keyboardSelectionID
                }
            }
            .onChange(of: focusedCameraID) { newValue in
                if let newValue {
                    keyboardSelectionID = newValue
                }
            }
            .onChange(of: keyboardSelectionID) { newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
                focusedCameraID = newValue
            }
            .onMoveCommand(perform: moveSelection)
            .onExitCommand {
                dismissDropdown()
            }
        }
    }

    @ViewBuilder
    private func cameraRow(for camera: CameraDeviceDescriptor) -> some View {
        let isSelected = selection == camera.uniqueID
        let isHovered = hoveredCameraID == camera.uniqueID
        let isKeyboardFocused = keyboardSelectionID == camera.uniqueID

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(camera.localizedName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Text(camera.detailsText)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Theme.textPrimary.opacity(0.82) : Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    rowBackground(
                        isSelected: isSelected,
                        isHovered: isHovered,
                        isKeyboardFocused: isKeyboardFocused
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    rowBorder(isSelected: isSelected, isKeyboardFocused: isKeyboardFocused),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func rowBackground(isSelected: Bool, isHovered: Bool, isKeyboardFocused: Bool) -> Color {
        if isSelected {
            return Theme.backgroundControlSelected
        }
        if isKeyboardFocused {
            return Theme.accent.opacity(0.12)
        }
        if isHovered {
            return Theme.backgroundControlHover
        }
        return .clear
    }

    private func rowBorder(isSelected: Bool, isKeyboardFocused: Bool) -> Color {
        if isSelected {
            return Theme.accent.opacity(0.28)
        }
        if isKeyboardFocused {
            return Theme.accent.opacity(0.22)
        }
        return .clear
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !cameras.isEmpty else { return }

        let cameraIDs = cameras.map(\.uniqueID)
        let currentID = keyboardSelectionID ?? selection ?? cameraIDs.first
        let currentIndex = currentID.flatMap { cameraIDs.firstIndex(of: $0) } ?? 0

        let nextIndex: Int
        switch direction {
        case .down:
            nextIndex = min(currentIndex + 1, cameraIDs.count - 1)
        case .up:
            nextIndex = max(currentIndex - 1, 0)
        default:
            return
        }

        keyboardSelectionID = cameraIDs[nextIndex]
    }

    private func toggleDropdown() {
        isPresented ? dismissDropdown() : presentDropdown(preferredSelection: selection ?? cameras.first?.uniqueID)
    }

    private func presentDropdown(preferredSelection: String?) {
        guard isEnabled, !cameras.isEmpty else { return }
        hoveredCameraID = nil
        keyboardSelectionID = preferredSelection ?? cameras.first?.uniqueID
        isPresented = true
    }

    private func dismissDropdown() {
        isPresented = false
        hoveredCameraID = nil
    }

    private func choose(_ camera: CameraDeviceDescriptor) {
        defer { dismissDropdown() }

        guard selection != camera.uniqueID else { return }
        selection = camera.uniqueID
        onSelection()
    }
}

private extension View {
    @ViewBuilder
    func cameraDropdownFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self.background(CameraDropdownFocusRingDisabler())
        }
    }
}

private struct CameraDropdownFocusRingDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraDropdownFocusRingDisablingView {
        CameraDropdownFocusRingDisablingView()
    }

    func updateNSView(_ nsView: CameraDropdownFocusRingDisablingView, context: Context) {
        DispatchQueue.main.async {
            nsView.disableEnclosingFocusRing()
        }
    }
}

private final class CameraDropdownFocusRingDisablingView: NSView {
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        disableEnclosingFocusRing()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disableEnclosingFocusRing()
    }

    func disableEnclosingFocusRing() {
        var currentView: NSView? = self
        while let view = currentView {
            view.focusRingType = .none
            currentView = view.superview
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
                    .toggleStyle(ControlSurfaceToggleStyle())
                    .labelsHidden()
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
                    .toggleStyle(ControlSurfaceToggleStyle())
                    .labelsHidden()
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
                    .toggleStyle(ControlSurfaceToggleStyle())
                    .labelsHidden()
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.controlBorder, lineWidth: 1)
                    )
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

private extension CameraDeviceDescriptor {
    var detailsText: String {
        let parts = [resolutionText, frameRateText].compactMap { $0 }
        if parts.isEmpty {
            return "Specs unavailable"
        }
        return parts.joined(separator: " • ")
    }

    var resolutionText: String? {
        guard let maxResolution else { return nil }
        return "\(Int(maxResolution.width))x\(Int(maxResolution.height))"
    }

    var frameRateText: String? {
        guard let maxFrameRate else { return nil }
        return String(format: "%.0f fps", maxFrameRate)
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
