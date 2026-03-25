import SwiftUI

@main
struct AutoFrameCamApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var appController
    @StateObject private var model = AppModel()

    init() {
        if let exitCode = HeadlessSystemExtensionCommand.runIfRequested() {
            exit(exitCode)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .background(
                    MainWindowObserver { window in
                        appController.registerMainWindow(window)
                    }
                )
                .onAppear {
                    appController.configureIfNeeded(model: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 650)
    }
}
