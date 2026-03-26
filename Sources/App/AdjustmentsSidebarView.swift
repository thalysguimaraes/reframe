import AutoFrameCore
import SwiftUI

struct AdjustmentsSidebarView: View {
    @ObservedObject var model: AppModel
    @State private var resetHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button — mirrors left sidebar
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.isAdjustmentsSidebarVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textLabel)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.sidebarPadding)
            .padding(.vertical, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Light
                    sectionBlock {
                        VStack(alignment: .leading, spacing: 10) {
                            SidebarSectionHeader(title: "Light", icon: "sun.max")

                            adjustmentSlider(
                                label: "Exposure",
                                value: $model.exposure,
                                range: -2.0 ... 2.0,
                                neutral: 0.0,
                                format: "%+.1f EV"
                            )

                            contrastSlider
                        }
                    }

                    sectionDivider

                    // Color
                    sectionBlock {
                        VStack(alignment: .leading, spacing: 10) {
                            SidebarSectionHeader(title: "Color", icon: "paintpalette")

                            colorSlider(
                                label: "Temperature",
                                value: $model.temperature,
                                range: 2000 ... 10000,
                                neutral: 6500,
                                format: "%.0f K",
                                gradient: Gradient(colors: [
                                    Color(hex: 0x4A90D9), // cool blue
                                    Color(hex: 0xD8D8E4), // neutral
                                    Color(hex: 0xE8B84D), // warm amber
                                ])
                            )

                            colorSlider(
                                label: "Tint",
                                value: $model.tint,
                                range: -150 ... 150,
                                neutral: 0,
                                format: "%+.0f",
                                gradient: Gradient(colors: [
                                    Color(hex: 0x5DAA68), // green
                                    Color(hex: 0xD8D8E4), // neutral
                                    Color(hex: 0xC96AA0), // magenta/pink
                                ])
                            )

                            colorSlider(
                                label: "Vibrance",
                                value: $model.vibrance,
                                range: -1.0 ... 1.0,
                                neutral: 0.0,
                                format: "%+.0f%%",
                                displayMultiplier: 100,
                                gradient: Gradient(colors: [
                                    Color(hex: 0x6A6A7A), // grey
                                    Color(hex: 0xE8A84D), // warm amber
                                    Color(hex: 0xD95050), // red
                                ])
                            )

                            colorSlider(
                                label: "Saturation",
                                value: $model.saturation,
                                range: 0.0 ... 2.0,
                                neutral: 1.0,
                                format: "%.0f%%",
                                displayMultiplier: 100,
                                gradient: Gradient(colors: [
                                    Color(hex: 0x6A6A7A), // grey
                                    Color(hex: 0x5DAA68), // green
                                    Color(hex: 0xE8B84D), // yellow
                                    Color(hex: 0xE87040), // orange
                                    Color(hex: 0xD95050), // red
                                ])
                            )
                        }
                    }

                    sectionDivider

                    // Sharpness
                    sectionBlock {
                        VStack(alignment: .leading, spacing: 10) {
                            SidebarSectionHeader(title: "Sharpness", icon: "diamond")

                            adjustmentSlider(
                                label: "Amount",
                                value: $model.sharpness,
                                range: 0.0 ... 2.0,
                                neutral: 0.0,
                                format: "%.0f%%",
                                displayMultiplier: 100
                            )
                        }
                    }

                    sectionDivider

                    // Background
                    sectionBlock {
                        VirtualBackgroundSectionView(model: model)
                    }

                    sectionDivider

                    // Reset
                    sectionBlock {
                        Button {
                            model.resetAdjustments()
                        } label: {
                            Text("Reset All")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(resetHovered ? Theme.textPrimary : Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    (resetHovered ? Theme.backgroundControlSelected : Theme.backgroundControl),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Theme.controlBorder, lineWidth: 1)
                                )
                                .scaleEffect(resetHovered ? 1.015 : 1.0)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                resetHovered = hovering
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: Theme.sidebarWidth)
        .background(Theme.backgroundSidebar)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.divider).frame(width: 1)
        }
    }

    // MARK: - Helpers

    private func sectionBlock<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        content()
            .padding(.horizontal, Theme.sidebarPadding)
            .padding(.vertical, 12)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.horizontal, Theme.sidebarPadding)
    }

    // Standard slider (exposure, sharpness)
    private func adjustmentSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        format: String,
        displayMultiplier: Double = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: format, value.wrappedValue * displayMultiplier))
                    .foregroundStyle(
                        abs(value.wrappedValue - neutral) < 0.01 ? Theme.textTertiary : Theme.textSecondary
                    )
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            Slider(value: value, in: range)
                .tint(Theme.accent)
                .onChange(of: value.wrappedValue) { _ in
                    model.persistSettings()
                }
        }
    }

    private var contrastControlBinding: Binding<Double> {
        Binding(
            get: { ContrastControlMapping.controlValue(for: model.contrast) },
            set: { model.contrast = ContrastControlMapping.contrast(for: $0) }
        )
    }

    private var contrastSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Contrast")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(model.contrastLabel)
                    .foregroundStyle(abs(model.contrast - 1.0) < 0.01 ? Theme.textTertiary : Theme.textSecondary)
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            Slider(value: contrastControlBinding, in: ContrastControlMapping.controlRange)
                .tint(Theme.accent)
                .onChange(of: model.contrast) { _ in
                    model.persistSettings()
                }

            HStack {
                Text("-50%")
                Spacer()
                Text("Neutral")
                Spacer()
                Text("+100%")
            }
            .font(.system(size: 10))
            .foregroundStyle(Theme.textTertiary)
        }
    }

    // Color slider with gradient track (temperature, tint, vibrance, saturation)
    private func colorSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        neutral: Double,
        format: String,
        displayMultiplier: Double = 1,
        gradient: Gradient
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(format: format, value.wrappedValue * displayMultiplier))
                    .foregroundStyle(
                        abs(value.wrappedValue - neutral) < 0.01 ? Theme.textTertiary : Theme.textSecondary
                    )
                    .monospacedDigit()
            }
            .font(.system(size: 12))

            GradientSlider(value: value, range: range, gradient: gradient)
                .onChange(of: value.wrappedValue) { _ in
                    model.persistSettings()
                }
        }
    }
}

// MARK: - Gradient Slider

private struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let gradient: Gradient

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - thumbSize
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let clampedFraction = min(max(fraction, 0), 1)
            let thumbX = thumbSize / 2 + width * clampedFraction

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: trackHeight / 2)
                    .fill(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .frame(width: thumbSize, height: thumbSize)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = (drag.location.x - thumbSize / 2) / width
                        let clamped = min(max(fraction, 0), 1)
                        value = range.lowerBound + (range.upperBound - range.lowerBound) * clamped
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Virtual Background

struct VirtualBackgroundSectionView: View {
    @ObservedObject var model: AppModel

    private var isEnabled: Bool {
        model.virtualBackgroundMode != .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SidebarSectionHeader(title: "Background", icon: "photo.on.rectangle")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue {
                            model.enableVirtualBackground(mode: .gradient)
                        } else {
                            model.enableVirtualBackground(mode: .off)
                        }
                    }
                ))
                    .toggleStyle(ControlSurfaceToggleStyle())
                    .labelsHidden()
            }

            if isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    // Use a grid layout that wraps: 4 columns
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
                    LazyVGrid(columns: columns, spacing: 8) {
                        // Gradient presets
                        ForEach(GradientPreset.allCases) { preset in
                            GradientPresetButton(
                                preset: preset,
                                isSelected: model.virtualBackgroundMode == .gradient
                                    && model.virtualBackgroundGradient == preset,
                                action: {
                                    model.virtualBackgroundGradient = preset
                                    model.enableVirtualBackground(mode: .gradient)
                                }
                            )
                        }

                        // Custom backgrounds
                        ForEach(model.customBackgrounds) { bg in
                            CustomBackgroundButton(
                                background: bg,
                                isSelected: model.virtualBackgroundMode == .customImage
                                    && model.selectedCustomBackgroundID == bg.id,
                                onSelect: { model.selectCustomBackground(bg.id) },
                                onDelete: { model.removeCustomBackground(bg.id) },
                                onRename: { newName in model.renameCustomBackground(bg.id, to: newName) }
                            )
                        }

                        // Add button
                        AddBackgroundButton {
                            model.importVirtualBackgroundImage()
                        }
                    }

                    Text("Replaces the background while keeping you sharp.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

private struct GradientPresetButton: View {
    let preset: GradientPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(gradientFill)
                    .frame(height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isSelected ? Theme.accent : Theme.controlBorder, lineWidth: isSelected ? 2 : 1)
                    )

                Text(preset.displayName)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var gradientFill: LinearGradient {
        switch preset {
        case .warmSunset:
            return LinearGradient(
                colors: [Color(red: 0.95, green: 0.45, blue: 0.25), Color(red: 0.45, green: 0.20, blue: 0.55)],
                startPoint: .bottom, endPoint: .top
            )
        case .coolOcean:
            return LinearGradient(
                colors: [Color(red: 0.10, green: 0.55, blue: 0.70), Color(red: 0.15, green: 0.20, blue: 0.45)],
                startPoint: .bottom, endPoint: .top
            )
        case .softLavender:
            return LinearGradient(
                colors: [Color(red: 0.85, green: 0.80, blue: 0.95), Color(red: 0.95, green: 0.92, blue: 0.98)],
                startPoint: .bottom, endPoint: .top
            )
        }
    }
}

private struct CustomBackgroundButton: View {
    let background: CustomBackground
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void

    @State private var isEditing = false
    @State private var editName = ""

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.backgroundControl)
                        .frame(height: 36)

                    let path = SharedStorage.containerDirectory()
                        .appendingPathComponent(background.fileName).path
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Theme.controlBorder, lineWidth: isSelected ? 2 : 1)
                )

                Text(background.name)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                editName = background.name
                isEditing = true
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .popover(isPresented: $isEditing) {
            VStack(spacing: 8) {
                Text("Rename Background")
                    .font(.system(size: 12, weight: .semibold))
                TextField("Name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit {
                        if !editName.isEmpty {
                            onRename(editName)
                        }
                        isEditing = false
                    }
                HStack {
                    Button("Cancel") { isEditing = false }
                        .buttonStyle(.bordered)
                    Button("Save") {
                        if !editName.isEmpty {
                            onRename(editName)
                        }
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }
            .padding(12)
        }
    }
}

private struct AddBackgroundButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.backgroundControl)
                    .frame(height: 36)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.controlBorder, lineWidth: 1)
                    )

                Text("Add")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }
}
