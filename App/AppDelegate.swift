import AppKit
import UniformTypeIdentifiers
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
        scheduleUpdateChecks()
        DefaultHandler.reassertClaimed()
    }

    // MARK: - Update check

    /// The app often runs for weeks from the menu bar, so checking only at
    /// launch is not enough: look every hour whether a check is due.
    private func scheduleUpdateChecks() {
        Task {
            while !Task.isCancelled {
                if UpdateChecker.isCheckDue {
                    await checkForUpdatesInBackground()
                }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    private func checkForUpdatesInBackground() async {
        guard let version = try? await UpdateChecker.newerVersion() else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Update Available")
        alert.informativeText = String(localized: "Version \(version) is available.")
        alert.addButton(withTitle: String(localized: "Download Update"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(UpdateChecker.downloadURL(for: version))
        }
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
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.accessibilityDescription = "Transmote"
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

// MARK: - Update check

/// Compares this build with the latest GitHub release. Installing is left to the user.
nonisolated enum UpdateChecker {
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    /// Seconds between automatic checks, 0 = never. Same key and default as the Settings picker.
    static let intervalKey = "updateCheckInterval"
    static let defaultInterval: TimeInterval = 86400
    private static let lastCheckKey = "lastUpdateCheck"

    static var isCheckDue: Bool {
        let interval = UserDefaults.standard.object(forKey: intervalKey) as? Double ?? defaultInterval
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        return interval > 0 && Date().timeIntervalSince1970 - last >= interval
    }

    private struct Release: Decodable { let tagName: String }

    /// The latest release's version if it is newer than this build, else nil.
    static func newerVersion() async throws -> String? {
        let url = URL(string: "https://api.github.com/repos/Kitround/Transmote/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let tag = try decoder.decode(Release.self, from: data).tagName
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: currentVersion) ? latest : nil
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    static func downloadURL(for version: String) -> URL {
        URL(string: "https://github.com/Kitround/Transmote/releases/download/v\(version)/Transmote.zip")!
    }
}

// MARK: - Default handler

/// Magnet links and .torrent files. While the user keeps Transmote as the
/// default in Settings, every launch re-claims the role if macOS lost it
/// (another client took over, an update, a stale record of an older build).
enum DefaultHandler: String, CaseIterable {
    case magnet, torrent

    private var claimedKey: String { "claimsDefault.\(rawValue)" }
    private static let torrentType = UTType(exportedAs: "org.bittorrent.torrent")

    /// The app macOS currently opens these with.
    var currentApp: URL? {
        switch self {
        case .magnet:  NSWorkspace.shared.urlForApplication(toOpen: URL(string: "magnet:")!)
        case .torrent: NSWorkspace.shared.urlForApplication(toOpen: Self.torrentType)
        }
    }

    var isOurs: Bool {
        currentApp?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    func claim() async throws {
        UserDefaults.standard.set(true, forKey: claimedKey)
        let appURL = Bundle.main.bundleURL
        // The preference is stored by bundle ID. A stale record of another
        // Transmote copy (older version, deleted folder) can win that lookup
        // and make macOS fall back to another client, so refresh ours first.
        LSRegisterURL(appURL as CFURL, true)
        try await setDefault(appURL)
    }

    /// Stops re-claiming the role and, if Transmote has it, hands it to the
    /// next app macOS ranks for it (e.g. Transmission). With no other app
    /// installed, Transmote stays the handler.
    func release() async throws {
        UserDefaults.standard.set(false, forKey: claimedKey)
        guard isOurs else { return }
        let candidates = switch self {
        case .magnet:  NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "magnet:")!)
        case .torrent: NSWorkspace.shared.urlsForApplications(toOpen: Self.torrentType)
        }
        let ourID = Bundle.main.bundleIdentifier?.lowercased()
        guard let other = candidates.first(where: { Bundle(url: $0)?.bundleIdentifier?.lowercased() != ourID }) else { return }
        try await setDefault(other)
    }

    private func setDefault(_ appURL: URL) async throws {
        switch self {
        case .magnet:  try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "magnet")
        case .torrent: try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: Self.torrentType)
        }
    }

    static func reassertClaimed() {
        for handler in allCases where UserDefaults.standard.bool(forKey: handler.claimedKey) && !handler.isOurs {
            Task { try? await handler.claim() }
        }
    }
}
