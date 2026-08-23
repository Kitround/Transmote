import AppKit
@preconcurrency import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    weak var store: TorrentStore?
    private var lastStatusTitle: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        setupStatusBar()
        requestNotificationPermission()
        observeWindowVisibility()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - URL / File handling
    //
    // Single ingress point for both magnet URL schemes and .torrent file
    // opens. Do not add .onOpenURL on the scene — having both paths
    // registered can double-add the same torrent.
    func application(_ application: NSApplication, open urls: [URL]) {
        showMainWindow()
        for url in urls {
            handleIncoming(url: url)
        }
    }

    func handleIncoming(url: URL) {
        Task { await add(url) }
    }

    /// On a cold launch the URL arrives before the scene has injected the
    /// store and before the first connection succeeds, so wait for both
    /// instead of dropping the magnet on the floor.
    private func add(_ url: URL) async {
        for _ in 0..<20 {
            if let store, store.connectionState.isConnected {
                if url.scheme == "magnet" {
                    _ = try? await store.addMagnet(url.absoluteString)
                } else if url.pathExtension.lowercased() == "torrent" {
                    _ = try? await store.addFile(at: url)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: - Window visibility tracking

    private func observeWindowVisibility() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSApplication.didHideNotification,         object: nil)
        nc.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSApplication.didUnhideNotification,       object: nil)
        nc.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didMiniaturizeNotification,       object: nil)
        nc.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didDeminiaturizeNotification,     object: nil)
        nc.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.willCloseNotification,            object: nil)
        nc.addObserver(self, selector: #selector(windowVisibilityChanged), name: NSWindow.didBecomeKeyNotification,         object: nil)
        nc.addObserver(self, selector: #selector(appActiveChanged),        name: NSApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(appActiveChanged),        name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func windowVisibilityChanged() {
        let visible = NSApp.windows.contains { w in
            w.isVisible && !w.isMiniaturized && w.styleMask.contains(.titled)
        }
        store?.isWindowVisible = visible
    }

    @objc private func appActiveChanged() {
        store?.isAppActive = NSApp.isActive
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "Transmote")
        button.image?.isTemplate = true

        statusMenu = NSMenu()
        statusMenu?.addItem(NSMenuItem(title: String(localized: "Open Transmote"), action: #selector(showMainWindow), keyEquivalent: ""))
        statusMenu?.addItem(NSMenuItem.separator())
        statusMenu?.addItem(NSMenuItem(title: String(localized: "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = statusMenu
    }

    func updateStatusBarTitle(download: Int, upload: Int) {
        let dl = ByteFormatter.transferRate(download)
        let ul = ByteFormatter.transferRate(upload)
        let title = " ↓\(dl) ↑\(ul)"
        guard title != lastStatusTitle else { return }
        lastStatusTitle = title
        statusItem?.button?.title = title
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.styleMask.contains(.titled) }?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyTorrentComplete(name: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Download Complete")
        content.body = name
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        // Trim delivered notifications history to keep memory bounded.
        UNUserNotificationCenter.current().getDeliveredNotifications { delivered in
            guard delivered.count > 20 else { return }
            let oldIDs = delivered
                .sorted { $0.date < $1.date }
                .prefix(delivered.count - 20)
                .map(\.request.identifier)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: oldIDs)
        }
    }
}
