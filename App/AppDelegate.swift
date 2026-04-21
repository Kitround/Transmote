import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    weak var store: TorrentStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        requestNotificationPermission()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - URL / File handling

    func application(_ application: NSApplication, open urls: [URL]) {
        showMainWindow()
        for url in urls {
            if url.scheme == "magnet" {
                Task { try? await store?.addMagnet(url.absoluteString) }
            } else if url.pathExtension.lowercased() == "torrent" {
                Task { try? await store?.addFile(at: url) }
            }
        }
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
        DispatchQueue.main.async { [weak self] in
            guard let button = self?.statusItem?.button else { return }
            let dl = ByteFormatter.transferRate(download)
            let ul = ByteFormatter.transferRate(upload)
            button.title = " ↓\(dl) ↑\(ul)"
        }
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
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
    }
}
