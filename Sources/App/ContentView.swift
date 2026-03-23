import AutoFrameCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(model: model)
                CameraPreviewView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            StatusBarView(model: model)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.black)
        .onAppear {
            model.onAppear()
        }
    }
}
