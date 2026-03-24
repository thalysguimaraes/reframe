import SwiftUI

@main
struct AutoFrameCamApp: App {
    init() {
        if let exitCode = HeadlessSystemExtensionCommand.runIfRequested() {
            exit(exitCode)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 650)
    }
}
