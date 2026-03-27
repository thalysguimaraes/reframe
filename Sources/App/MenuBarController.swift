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
        if let window = resolvedMainWindow() {
            model.setMainWindowVisible(window.isVisible)
        }
        isConfigured = true
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }

        mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
        model?.setMainWindowVisible(window.isVisible)

        if window.title.isEmpty {
            window.title = "Reframe"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshPresentationOptions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.showInMenuBar == true else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Quit Reframe?"
        alert.informativeText = "The virtual camera and menu bar controls will stop running."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
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
        NSApp.setActivationPolicy(.accessory)
        model?.setMainWindowVisible(false)
        return false
    }

    func showMainWindow() {
        guard let window = resolvedMainWindow() else { return }

        NSApp.setActivationPolicy(.regular)
        model?.setMainWindowVisible(true)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === resolvedMainWindow() else { return }
        model?.setMainWindowVisible(false)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === resolvedMainWindow() else { return }
        model?.setMainWindowVisible(false)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === resolvedMainWindow() else { return }
        model?.setMainWindowVisible(true)
    }

    private func bindModel(_ model: AppModel) {
        model.$showInMenuBar
            .removeDuplicates()
            .sink { [weak self] _ in
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

        // Only resize when the onboarding lifecycle is active: skip the initial
        // false emission for users who have already completed onboarding so we
        // don't override their saved window position on every launch.
        model.$showingOnboarding
            .removeDuplicates()
            .drop(while: { !$0 })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showing in
                self?.applyWindowSize(forOnboarding: showing)
            }
            .store(in: &cancellables)
    }

    private func applyWindowSize(forOnboarding isOnboarding: Bool) {
        guard let window = resolvedMainWindow() else { return }

        if isOnboarding {
            let size = NSSize(width: 440, height: 580)
            window.minSize = size
            window.maxSize = size
            let screen = window.screen ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                let origin = NSPoint(
                    x: visibleFrame.midX - size.width / 2,
                    y: visibleFrame.midY - size.height / 2
                )
                window.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
            } else {
                window.setContentSize(size)
            }
        } else {
            let size = NSSize(width: 1000, height: 650)
            window.minSize = NSSize(width: 900, height: 600)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            let screen = window.screen ?? NSScreen.main
            if let visibleFrame = screen?.visibleFrame {
                let origin = NSPoint(
                    x: visibleFrame.midX - size.width / 2,
                    y: visibleFrame.midY - size.height / 2
                )
                window.setFrame(NSRect(origin: origin, size: size), display: true, animate: true)
            } else {
                window.setContentSize(size)
            }
        }
    }

    private func refreshPresentationOptions() {
        guard let model else { return }

        menuBarController.setVisible(model.showInMenuBar)
        menuBarController.updateStatusAppearance()

        let hasVisibleWindow = resolvedMainWindow()?.isVisible == true
        if hasVisibleWindow || !model.showInMenuBar {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
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
final class MenuBarController: NSObject, NSPopoverDelegate {
    private weak var model: AppModel?
    private var onExpand: (() -> Void)?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hostingController: NSHostingController<MiniPreviewView>?

    func configure(model: AppModel, onExpand: @escaping () -> Void) {
        self.model = model
        self.onExpand = onExpand

        popover.delegate = self
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

    var isPopoverVisible: Bool {
        popover.isShown
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func updateStatusAppearance() {
        guard let button = statusItem?.button, let model else { return }

        if let mascotImage = NSImage(named: "MenuBarIcon") {
            mascotImage.isTemplate = true
            mascotImage.size = NSSize(width: 18, height: 18)
            button.image = mascotImage
        } else {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            let image = NSImage(
                systemSymbolName: "camera.fill",
                accessibilityDescription: "Reframe"
            )?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            button.image = image
        }

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

        model?.setMenuBarPopoverVisible(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.becomeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        model?.setMenuBarPopoverVisible(false)
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
        model?.setMenuBarPopoverVisible(false)

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
