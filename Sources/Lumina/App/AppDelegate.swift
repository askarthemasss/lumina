import AppKit
import SwiftUI

/// Owns the single main window, the menu-bar-level quick search panel, and the
/// global shortcut. A manually managed NSWindow keeps Lumina a focused
/// single-window app: closing the window does not discard its state, and the
/// quick search panel can reopen it at any time.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var hotKeyManager: HotKeyManager?
    private var quickSearchController: QuickSearchPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyAppearance()

        guard let model = AppEnvironment.shared.model else {
            showStartupWindow()
            return
        }

        quickSearchController = QuickSearchPanelController(model: model)
        hotKeyManager = HotKeyManager()
        registerGlobalShortcut(for: model)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowQuickSearch),
            name: .luminaShowQuickSearch,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainWindow),
            name: .luminaOpenMainWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutChanged),
            name: .luminaShortcutChanged,
            object: nil
        )

        // A tiny delay lets SwiftUI finish constructing its scenes before the
        // first window becomes visible. There is no flash: the app is still in
        // its launch transaction.
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Notifications

    @objc private func handleShowQuickSearch() {
        quickSearchController?.show()
    }

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    @objc private func handleShortcutChanged() {
        guard let model = AppEnvironment.shared.model else { return }
        registerGlobalShortcut(for: model)
    }

    // MARK: Windows

    func showMainWindow() {
        guard let model = AppEnvironment.shared.model else {
            showStartupWindow()
            return
        }
        if mainWindow == nil {
            mainWindow = makeMainWindow(model: model)
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        applyAppearance()
    }

    private func makeMainWindow(model: AppModel) -> NSWindow {
        let root = RootView()
            .environment(model)
            .environment(model.settings)
            .tint(model.settings.accent.color)
            .preferredColorScheme(model.settings.appearance.colorScheme)

        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Lumina"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 980, height: 640)
        window.setContentSize(NSSize(width: 1_240, height: 800))
        window.setFrameAutosaveName("LuminaMainWindow")
        if window.frame.width < 980 || window.frame.height < 640 {
            window.setContentSize(NSSize(width: 1_240, height: 800))
            window.center()
        }
        window.backgroundColor = .windowBackgroundColor
        return window
    }

    private func showStartupWindow() {
        let root = StartupFailureView(
            message: AppEnvironment.shared.startupError ?? "Lumina couldn't open its local database."
        )
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.title = "Lumina"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 380))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    // MARK: Shortcut & appearance

    private func registerGlobalShortcut(for model: AppModel) {
        guard let hotKeyManager else { return }
        let success = hotKeyManager.register(model.settings.shortcut)
        if success {
            model.infoMessage = "Quick Search is available with \(model.settings.shortcut.display)."
        } else {
            model.errorBanner = UserFacingError(
                "Shortcut unavailable",
                message: "\(model.settings.shortcut.display) is already used by another app. Choose another shortcut in Settings → General."
            )
        }
    }

    private func applyAppearance() {
        guard let model = AppEnvironment.shared.model else { return }
        switch model.settings.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        mainWindow?.appearance = NSApp.appearance
    }
}

// MARK: - Quick search panel

@MainActor
final class QuickSearchPanelController {
    private let model: AppModel
    private var panel: QuickSearchPanel?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        let root = QuickSearchView(onClose: { [weak self] in
            self?.hide()
        })
        .environment(model)
        .environment(model.settings)
        .tint(model.settings.accent.color)
        .preferredColorScheme(model.settings.appearance.colorScheme)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 780, height: 520)
        panel.contentView = hosting

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let field = panel.contentView?.descendant(of: NSTextField.self) {
            panel.makeFirstResponder(field)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> QuickSearchPanel {
        let panel = QuickSearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 150
        panel.setFrameOrigin(NSPoint(x: max(visible.minX + 20, x), y: max(visible.minY + 20, y)))
    }
}

final class QuickSearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

private extension NSView {
    func descendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let match = subview.descendant(of: type) { return match }
        }
        return nil
    }
}
