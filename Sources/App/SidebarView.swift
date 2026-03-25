import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar toggle — aligned with top bar height
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        model.isSidebarVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textLabel)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, Theme.sidebarPadding)
            .padding(.vertical, 12)

            // Sections with dividers
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionBlock { CameraSectionView(model: model) }
                    sectionDivider
                    sectionBlock { OutputSectionView(model: model) }
                    sectionDivider
                    sectionBlock { FramingSectionView(model: model) }
                    sectionDivider
                    sectionBlock { TrackingSectionView(model: model) }
                    sectionDivider
                    sectionBlock { ZoomSectionView(model: model) }
                    sectionDivider
                    sectionBlock { PortraitSectionView(model: model) }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: Theme.sidebarWidth)
        .background(Theme.backgroundSidebar)
    }

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
}
