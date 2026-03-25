import SwiftUI

struct ControlSurfaceToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Theme.accent : Theme.backgroundToggleOff)
                    .overlay(
                        Capsule()
                            .strokeBorder(Theme.controlBorder, lineWidth: 1)
                    )

                Circle()
                    .fill(Color.white.opacity(isEnabled ? 1 : 0.92))
                    .shadow(color: Theme.controlShadow.opacity(0.18), radius: 4, y: 1)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
