import SwiftUI

@main
struct ReframeApp: App {
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
        .defaultSize(width: 440, height: 580)
    }
}
