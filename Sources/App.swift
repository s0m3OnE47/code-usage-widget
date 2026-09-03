import SwiftUI
import AppKit
import ServiceManagement

class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            if !isKeyWindow { makeKeyAndOrderFront(nil) }
        }
        super.sendEvent(event)
    }
}

final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    var contextMenu: NSMenu?
    weak var appDelegate: WidgetAppDelegate?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        appDelegate?.refreshContextMenu()
        showContextMenu(for: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu
    }

    private func showContextMenu(for event: NSEvent) {
        guard let menu = contextMenu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

@main
enum AppLauncher {
    static func main() {
        WidgetAppDelegate.run()
    }
}

@MainActor
final class WidgetAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let aggregator = UsageAggregator()
    let widgetState = WidgetState()
    weak var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var showPanelItem: NSMenuItem?
    private var floatingWindow: WidgetWindow?

    private static var retained: WidgetAppDelegate?
    private static let showPanelKey = "showFloatingPanel"

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WidgetAppDelegate()
        retained = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        removeLegacyLaunchAgentIfNeeded()
        setupStatusItem()
        setupKeyboardShortcuts()
        aggregator.start()

        if UserDefaults.standard.bool(forKey: Self.showPanelKey) {
            showFloatingPanel()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: "AI Usage")
            button.image?.isTemplate = true
            button.toolTip = "AI Usage"
        }
        item.menu = buildContextMenu()
        statusItem = item
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let refresh = NSMenuItem(title: "Refresh", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command]
        refresh.target = self
        menu.addItem(refresh)

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launchAtLoginItem = launch
        menu.addItem(launch)

        let panel = NSMenuItem(title: "Show Floating Panel", action: #selector(menuToggleFloatingPanel), keyEquivalent: "")
        panel.target = self
        showPanelItem = panel
        menu.addItem(panel)

        let settings = NSMenuItem(title: "Open Config", action: #selector(menuOpenConfig), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = []
        quit.target = self
        menu.addItem(quit)

        refreshContextMenu()
        return menu
    }

    func refreshContextMenu() {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let showing = floatingWindow?.isVisible == true
        showPanelItem?.state = showing ? .on : .off
    }

    /// Old installs used a LaunchAgent plist, which triggers repeated macOS background-activity alerts.
    private func removeLegacyLaunchAgentIfNeeded() {
        let agentPath = NSHomeDirectory() + "/Library/LaunchAgents/com.anakin.code-usage-widget.plist"
        guard FileManager.default.fileExists(atPath: agentPath) else { return }

        let uid = getuid()
        let service = "gui/\(uid)/com.anakin.code-usage-widget"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", service]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(atPath: agentPath)
    }

    @objc func menuToggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch at login: \(error.localizedDescription)")
        }
        refreshContextMenu()
    }

    @objc func menuToggleFloatingPanel() {
        if floatingWindow?.isVisible == true {
            hideFloatingPanel()
        } else {
            showFloatingPanel()
        }
        refreshContextMenu()
    }

    private func showFloatingPanel() {
        let win = floatingWindow ?? makeFloatingWindow()
        floatingWindow = win
        window = win
        clampToVisibleScreen(win)
        setupObservers(win: win)
        setupDragMonitor(win: win)
        win.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set(true, forKey: Self.showPanelKey)
    }

    private func hideFloatingPanel() {
        floatingWindow?.orderOut(nil)
        UserDefaults.standard.set(false, forKey: Self.showPanelKey)
    }

    private func makeFloatingWindow() -> WidgetWindow {
        let size = WidgetLayout.size
        let win = WidgetWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = false
        win.isMovable = false
        win.collectionBehavior = [.canJoinAllSpaces]
        win.minSize = size
        win.maxSize = size

        let root = WidgetView()
            .environmentObject(aggregator)
            .environmentObject(widgetState)
        let host = WidgetHostingView(rootView: root)
        host.appDelegate = self
        host.frame.size = size
        host.autoresizingMask = [.width, .height]
        win.contentView = host
        host.wantsLayer = true
        host.layer?.cornerRadius = 22
        host.layer?.masksToBounds = true
        host.contextMenu = statusItem?.menu
        return win
    }

    private func restoreWindowPosition(win: NSWindow, size: CGSize) {
        if let origin = ConfigLoader.loadWindowPosition() {
            win.setFrameOrigin(WindowPositioning.clampedSnap(origin: origin, size: size, window: win))
            return
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = WindowPositioning.clampedSnap(
                origin: NSPoint(
                    x: frame.maxX - size.width - WidgetLayout.gridSpacing,
                    y: frame.maxY - size.height - WidgetLayout.gridSpacing
                ),
                size: size,
                window: win
            )
            win.setFrameOrigin(origin)
        }
    }

    private func clampToVisibleScreen(_ win: NSWindow) {
        restoreWindowPosition(win: win, size: win.frame.size)
        let origin = WindowPositioning.clampedSnap(origin: win.frame.origin, size: win.frame.size, window: win)
        win.setFrameOrigin(origin)
        ConfigLoader.saveWindowPosition(origin)
    }

    private func setupObservers(win: NSWindow) {
        guard !observersReady else { return }
        observersReady = true
        let nc = NotificationCenter.default

        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetState.focused = true }
        }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetState.focused = false }
        }
    }

    private func setupDragMonitor(win: NSWindow) {
        if dragMonitor != nil { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, let window = self.floatingWindow, window.isVisible else { return event }
            return self.handleDragEvent(event, window: window)
        }
    }

    private func handleDragEvent(_ event: NSEvent, window: NSWindow) -> NSEvent? {
        guard window.isVisible else { return event }
        switch event.type {
        case .leftMouseDown:
            guard shouldBeginDrag(event: event, window: window) else { return event }
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = window.frame.origin
            widgetState.dragging = true
            return event

        case .leftMouseDragged:
            guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else { return event }
            let mouse = NSEvent.mouseLocation
            let origin = NSPoint(
                x: startOrigin.x + (mouse.x - startMouse.x),
                y: startOrigin.y + (mouse.y - startMouse.y)
            )
            let visible = WindowPositioning.visibleFrame(for: window)
            window.setFrameOrigin(WindowPositioning.clamp(origin: origin, size: window.frame.size, to: visible))
            return nil

        case .leftMouseUp:
            guard dragStartMouse != nil else { return event }
            finishDrag(window: window)
            return nil

        default:
            return event
        }
    }

    private func shouldBeginDrag(event: NSEvent, window: NSWindow) -> Bool {
        guard event.window === window else { return false }
        guard let contentView = window.contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        guard let hit = contentView.hitTest(point) else { return true }
        return !WindowPositioning.isDragExcludedView(hit)
    }

    private func finishDrag(window: NSWindow) {
        let origin = WindowPositioning.clampedSnap(origin: window.frame.origin, size: window.frame.size, window: window)
        window.setFrameOrigin(origin)
        ConfigLoader.saveWindowPosition(origin)
        dragStartMouse = nil
        dragStartOrigin = nil
        widgetState.dragging = false
    }

    private var keyMonitor: Any?
    private var dragMonitor: Any?
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var observersReady = false

    private func setupKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "r" {
                self.performRefresh()
                return nil
            }
            return event
        }
    }

    private func performRefresh() {
        aggregator.refresh()
    }

    @objc func menuRefresh() {
        performRefresh()
    }

    @objc func menuOpenConfig() {
        let path = ConfigLoader.configPath
        let dir = ConfigLoader.configDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            let example = Bundle.main.path(forResource: "config.example", ofType: "json")
                ?? (FileManager.default.currentDirectoryPath + "/config.example.json")
            if FileManager.default.fileExists(atPath: example) {
                try? FileManager.default.copyItem(atPath: example, toPath: path)
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc func menuQuit() {
        aggregator.stop()
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshContextMenu()
    }
}
