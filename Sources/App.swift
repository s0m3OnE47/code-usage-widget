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
final class WidgetAppDelegate: NSObject, NSApplicationDelegate {
    let aggregator = UsageAggregator()
    let widgetState = WidgetState()
    weak var window: NSWindow?
    private var launchAtLoginItem: NSMenuItem?

    private static var retained: WidgetAppDelegate?

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = WidgetAppDelegate()
        retained = delegate
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        window = win

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

        host.contextMenu = buildContextMenu()
        removeLegacyLaunchAgentIfNeeded()
        clampToVisibleScreen(win)
        setupObservers(win: win)
        setupKeyboardShortcuts()

        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: false)
        aggregator.start()
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let refresh = NSMenuItem(title: "Refresh", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command]
        refresh.target = self
        menu.addItem(refresh)

        let launch = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launchAtLoginItem = launch
        menu.addItem(launch)

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

    private func restoreWindowPosition(win: NSWindow, size: CGSize) {
        if let origin = ConfigLoader.loadWindowPosition() {
            win.setFrameOrigin(origin)
            return
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            win.setFrameOrigin(NSPoint(
                x: round(frame.maxX - size.width - 24),
                y: round(frame.maxY - size.height - 24)
            ))
        }
    }

    private func clampToVisibleScreen(_ win: NSWindow) {
        restoreWindowPosition(win: win, size: win.frame.size)
        guard let screen = win.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = win.frame.origin
        let size = win.frame.size
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        win.setFrameOrigin(origin)
        ConfigLoader.saveWindowPosition(origin)
    }

    private func setupObservers(win: NSWindow) {
        let nc = NotificationCenter.default

        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetState.focused = true }
        }
        nc.addObserver(forName: NSWindow.didResignKeyNotification, object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetState.focused = false }
        }
        nc.addObserver(forName: NSWindow.willMoveNotification, object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.widgetState.dragging = true }
        }
        nc.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let w = self.window, let screen = w.screen else { return }
                self.widgetState.dragging = false
                let visible = screen.visibleFrame
                let grid: CGFloat = 24
                var origin = w.frame.origin
                origin.x = round((origin.x - visible.minX) / grid) * grid + visible.minX
                origin.y = round((origin.y - visible.minY) / grid) * grid + visible.minY
                origin.x = max(visible.minX, min(origin.x, visible.maxX - w.frame.width))
                origin.y = max(visible.minY, min(origin.y, visible.maxY - w.frame.height))
                w.setFrameOrigin(origin)
                ConfigLoader.saveWindowPosition(origin)
            }
        }
    }

    private var keyMonitor: Any?

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
}
