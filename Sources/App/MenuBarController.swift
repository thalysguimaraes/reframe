import AppKit
import Combine
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private weak var model: AppModel?
    private weak var mainWindow: NSWindow?
    private let menuBarController = MenuBarController()
    private var cancellables: Set<AnyCancellable> = []
    private var isConfigured = false

    func configureIfNeeded(model: AppModel) {
        guard !isConfigured else { return }

        self.model = model
        menuBarController.configure(model: model) { [weak self] in
            self?.showMainWindow()
        }
        bindModel(model)
        refreshPresentationOptions()
        isConfigured = true
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }

        mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false

        if window.title.isEmpty {
            window.title = "Reframe"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshPresentationOptions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(model?.shouldKeepRunningInBackground ?? false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === resolvedMainWindow(), model?.shouldKeepRunningInBackground == true else {
            return true
        }

        sender.orderOut(nil)
        return false
    }

    func showMainWindow() {
        guard let window = resolvedMainWindow() else { return }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func bindModel(_ model: AppModel) {
        Publishers.CombineLatest(
            model.$showInMenuBar.removeDuplicates(),
            model.$showDockIcon.removeDuplicates()
        )
        .sink { [weak self] _, _ in
            self?.refreshPresentationOptions()
        }
        .store(in: &cancellables)

        model.$previewState
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.menuBarController.updateStatusAppearance()
            }
            .store(in: &cancellables)

        model.$pipelineActivity
            .map { $0?.statusMessage ?? "" }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.menuBarController.updateStatusAppearance()
            }
            .store(in: &cancellables)

        model.$statusMessage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.menuBarController.updateStatusAppearance()
            }
            .store(in: &cancellables)
    }

    private func refreshPresentationOptions() {
        guard let model else { return }

        menuBarController.setVisible(model.showInMenuBar)
        menuBarController.updateStatusAppearance()
        updateActivationPolicy(using: model)
    }

    private func updateActivationPolicy(using model: AppModel) {
        let policy: NSApplication.ActivationPolicy = model.effectiveShowsDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }

    private func resolvedMainWindow() -> NSWindow? {
        if let mainWindow {
            return mainWindow
        }

        if let window = NSApp.windows.first(where: { $0.canBecomeMain || $0.canBecomeKey }) {
            registerMainWindow(window)
            return window
        }

        return nil
    }
}

@MainActor
final class MenuBarController: NSObject {
    private weak var model: AppModel?
    private var onExpand: (() -> Void)?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hostingController: NSHostingController<MiniPreviewView>?

    func configure(model: AppModel, onExpand: @escaping () -> Void) {
        self.model = model
        self.onExpand = onExpand

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 500)

        let hostingController = NSHostingController(
            rootView: MiniPreviewView(model: model) { [weak self] in
                self?.expandIntoMainWindow()
            }
        )
        self.hostingController = hostingController
        popover.contentViewController = hostingController

        setVisible(model.showInMenuBar)
        updateStatusAppearance()
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func updateStatusAppearance() {
        guard let button = statusItem?.button, let model else { return }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(
            systemSymbolName: model.menuBarIconSymbolName,
            accessibilityDescription: "Reframe"
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = false

        button.image = image
        button.contentTintColor = model.menuBarIconTintColor
        button.imagePosition = .imageOnly
        button.toolTip = model.statusMessage
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        self.statusItem = statusItem
    }

    private func removeStatusItem() {
        closePopover()

        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func expandIntoMainWindow() {
        closePopover()
        onExpand?()
    }
}

struct MainWindowObserver: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
