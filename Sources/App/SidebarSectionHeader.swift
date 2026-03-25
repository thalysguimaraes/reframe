import SwiftUI

struct SidebarSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
                .textCase(.uppercase)
                .tracking(0.55)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textLabel)
    }
}
