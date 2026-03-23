import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                CameraSectionView(model: model)
                Divider()
                OutputSectionView(model: model)
                Divider()
                FramingSectionView(model: model)
                Divider()
                TrackingSectionView(model: model)
                Divider()
                ZoomSectionView(model: model)
                Divider()
                VirtualCameraSectionView(model: model)
            }
            .padding(16)
        }
        .frame(width: 260)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}
