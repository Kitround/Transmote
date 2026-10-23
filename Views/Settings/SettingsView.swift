import SwiftUI
import AppKit

struct SettingsView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            BandwidthSettingsTab()
                .tabItem { Label("Bandwidth", systemImage: "speedometer") }

            PeersSettingsTab()
                .tabItem { Label("Peers", systemImage: "person.2") }

            QueueSettingsTab()
                .tabItem { Label("Queue", systemImage: "list.number") }
        }
        .frame(width: 480)
        .onAppear { Task { await store.refreshSession() } }
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @Environment(TorrentStore.self) private var store
    @State private var downloadDir = ""
    @AppStorage("pollingInterval") private var pollingInterval: Double = 3
    @State private var selectedLanguage: String = {
        let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String]
        if let first = langs?.first {
            if first.hasPrefix("fr") { return "fr" }
            if first.hasPrefix("en") { return "en" }
            if first.hasPrefix("de") { return "de" }
            if first.hasPrefix("es") { return "es" }
            if first.hasPrefix("zh-Hans") { return "zh-Hans" }
        }
        return "system"
    }()
    @State private var showRestartAlert = false
    @State private var defaultAppMessage: String? = nil
    /// What macOS currently opens each kind with; nil when it is Transmote.
    @State private var otherDefaultApp: [DefaultHandler: String] = [:]
    @State private var defaultsChecked = false
    @AppStorage(UpdateChecker.intervalKey) private var updateCheckInterval = UpdateChecker.defaultInterval
    @State private var checkingForUpdates = false
    @State private var availableVersion: String? = nil
    @State private var updateMessage: String? = nil

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $selectedLanguage) {
                    Text("System Default").tag("system")
                    Text("English").tag("en")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("简体中文").tag("zh-Hans")
                }
                .onChange(of: selectedLanguage) { _, newValue in
                    if newValue == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    }
                    UserDefaults.standard.synchronize()
                    showRestartAlert = true
                }
            }

            Section("Updates") {
                Picker("Automatic check", selection: $updateCheckInterval) {
                    Text("Never").tag(0.0)
                    Text("Daily").tag(86400.0)
                    Text("Weekly").tag(604800.0)
                    Text("Monthly").tag(2592000.0)
                }
                HStack {
                    Text("Version \(UpdateChecker.currentVersion)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates") {
                        Task { await checkUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(checkingForUpdates)
                }
                if let version = availableVersion {
                    HStack {
                        Text("Version \(version) is available.")
                        Spacer()
                        Button("Download Update") {
                            NSWorkspace.shared.open(UpdateChecker.downloadURL(for: version))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if let msg = updateMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Default App") {
                defaultAppRow("Magnet links", .magnet,
                              success: String(localized: "✓ Transmote is now the default app for magnet links."))
                defaultAppRow(".torrent files", .torrent,
                              success: String(localized: "✓ Transmote is now the default app for .torrent files."))
                if let msg = defaultAppMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("✓") ? .green : .secondary)
                }
            }

            Section("Downloads") {
                HStack {
                    // The section header already names it; a label here squeezes the path.
                    TextField("Download folder", text: $downloadDir, prompt: Text("Download folder"))
                        .labelsHidden()
                        .onSubmit { applyDownloadDir() }
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.begin { resp in
                            guard resp == .OK, let url = panel.url else { return }
                            downloadDir = url.path
                            applyDownloadDir()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Refresh Interval") {
                Picker("Refresh Interval", selection: $pollingInterval) {
                    Text("Every 1 s").tag(1.0)
                    Text("Every 2 s").tag(2.0)
                    Text("Every 3 s").tag(3.0)
                    Text("Every 5 s").tag(5.0)
                    Text("Every 10 s").tag(10.0)
                    Text("Every 15 s").tag(15.0)
                    Text("Every 30 s").tag(30.0)
                }
            }

            Section {
                if let session = store.session {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Transmission Version").foregroundStyle(.secondary)
                            Spacer()
                            Text(session.version ?? "—")
                        }
                        HStack {
                            Text("RPC Version").foregroundStyle(.secondary)
                            Spacer()
                            Text(session.rpcVersion.map { "\($0)" } ?? "—")
                        }
                    }
                }
            } header: {
                Text("About the Server")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            downloadDir = store.session?.downloadDir ?? ""
            refreshDefaultApps()
        }
        // The user may have changed the default in Finder or another client meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultApps()
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                // `open` while we're still running just reactivates this instance,
                // so wait for this process to exit before reopening the app.
                let pid = ProcessInfo.processInfo.processIdentifier
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/sh")
                task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
                try? task.run()
                NSApp.terminate(nil)
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Please restart Transmote to apply the language change.")
        }
        .padding()
    }

    private func checkUpdates() async {
        checkingForUpdates = true
        defer { checkingForUpdates = false }
        do {
            availableVersion = try await UpdateChecker.newerVersion()
            updateMessage = availableVersion == nil ? String(localized: "Transmote is up to date.") : nil
        } catch {
            availableVersion = nil
            updateMessage = String(localized: "Update check failed.")
        }
    }

    private func applyDownloadDir() {
        guard !downloadDir.isEmpty else { return }
        Task {
            try? await store.updateSession(settings: ["download-dir": AnyCodable(downloadDir)])
        }
    }

    private func defaultAppRow(_ title: LocalizedStringKey, _ handler: DefaultHandler, success: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if defaultsChecked {
                    Group {
                        if let other = otherDefaultApp[handler] {
                            Text("Currently: \(other)")
                                .foregroundStyle(.secondary)
                        } else {
                            // Label's icon gap is too wide for a caption.
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Transmote is the default")
                            }
                            .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                }
            }
            Spacer()
            if defaultsChecked {
                Group {
                    if otherDefaultApp[handler] != nil {
                        Button("Set as default") {
                            setDefault(handler, success: success)
                        }
                    } else {
                        Button("Stop using as default") {
                            stopDefault(handler)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }
        }
    }

    private func refreshDefaultApps() {
        otherDefaultApp = [:]
        for handler in DefaultHandler.allCases where !handler.isOurs {
            otherDefaultApp[handler] = handler.currentApp.map { FileManager.default.displayName(atPath: $0.path) } ?? "—"
        }
        defaultsChecked = true
    }

    private func setDefault(_ handler: DefaultHandler, success: String) {
        Task {
            defer { refreshDefaultApps() }
            do {
                try await handler.claim()
                // Launch Services can accept the preference and still resolve
                // another app, so report what it actually picks.
                defaultAppMessage = handler.isOurs
                    ? success
                    : String(localized: "Failed: macOS still opens them with \(handler.currentApp?.path ?? "—").")
            } catch {
                defaultAppMessage = String(localized: "Failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopDefault(_ handler: DefaultHandler) {
        Task {
            defer { refreshDefaultApps() }
            do {
                try await handler.release()
                defaultAppMessage = handler.isOurs
                    ? String(localized: "No other installed app can open them, so Transmote stays the default.")
                    : nil
            } catch {
                defaultAppMessage = String(localized: "Failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Bandwidth Tab

struct BandwidthSettingsTab: View {
    @Environment(TorrentStore.self) private var store
    @State private var dlLimitEnabled = false
    @State private var dlLimitMB: Double = 1
    @State private var ulLimitEnabled = false
    @State private var ulLimitMB: Double = 1
    @State private var altDlMB: Double = 0.5
    @State private var altUlMB: Double = 0.125
    @State private var altEnabled = false

    var body: some View {
        Form {
            Section("Global Speed") {
                Toggle("Limit Download", isOn: $dlLimitEnabled)
                if dlLimitEnabled {
                    SpeedField(label: "↓ Limit", valueMB: $dlLimitMB)
                }

                Toggle("Limit Upload", isOn: $ulLimitEnabled)
                if ulLimitEnabled {
                    SpeedField(label: "↑ Limit", valueMB: $ulLimitMB)
                }
            }

            Section("Turtle Mode (alternative speed)") {
                Toggle("Enable Turtle Mode", isOn: $altEnabled)
                SpeedField(label: "↓ Limit", valueMB: $altDlMB)
                SpeedField(label: "↑ Limit", valueMB: $altUlMB)
            }

            Section {
                Button("Apply") { applyBandwidth() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromSession() }
        .padding()
    }

    private func loadFromSession() {
        guard let session = store.session else { return }
        dlLimitEnabled = session.speedLimitDownEnabled ?? false
        dlLimitMB = Double(session.speedLimitDown ?? 1024) / 1024.0
        ulLimitEnabled = session.speedLimitUpEnabled ?? false
        ulLimitMB = Double(session.speedLimitUp ?? 1024) / 1024.0
        altDlMB = Double(session.altSpeedDown ?? 512) / 1024.0
        altUlMB = Double(session.altSpeedUp ?? 128) / 1024.0
        altEnabled = session.altSpeedEnabled ?? false
    }

    private func applyBandwidth() {
        Task {
            try? await store.updateSession(settings: [
                "speed-limit-down":         AnyCodable(max(1, Int(dlLimitMB * 1024))),
                "speed-limit-down-enabled": AnyCodable(dlLimitEnabled),
                "speed-limit-up":           AnyCodable(max(1, Int(ulLimitMB * 1024))),
                "speed-limit-up-enabled":   AnyCodable(ulLimitEnabled),
                "alt-speed-down":           AnyCodable(max(1, Int(altDlMB * 1024))),
                "alt-speed-up":             AnyCodable(max(1, Int(altUlMB * 1024))),
                "alt-speed-enabled":        AnyCodable(altEnabled)
            ])
        }
    }
}

// MARK: - Numeric Fields

/// Value-bound TextFields commit on focus loss as well as on Return, and
/// parse the locale's decimal separator — no manual text mirroring needed.
struct SpeedField: View {
    let label: LocalizedStringKey
    @Binding var valueMB: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $valueMB, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            Text("MB/s")
                .foregroundStyle(.secondary)
        }
    }
}

struct RatioField: View {
    let label: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Peers Tab

struct PeersSettingsTab: View {
    @Environment(TorrentStore.self) private var store
    @State private var globalLimit: Int = 200
    @State private var perTorrentLimit: Int = 50
    @State private var peerPort: Int = 51413
    @State private var portRandom = false
    @State private var portForwarding = false
    @State private var encryption = "preferred"

    var body: some View {
        Form {
            Section("Limits") {
                HStack {
                    Text("Max global peers")
                    Spacer()
                    TextField("", value: $globalLimit, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Peers per torrent")
                    Spacer()
                    TextField("", value: $perTorrentLimit, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Network") {
                HStack {
                    Text("Incoming port")
                    Spacer()
                    TextField("", value: $peerPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Random port on startup", isOn: $portRandom)
                Toggle("UPnP / NAT-PMP", isOn: $portForwarding)
            }

            Section("Encryption") {
                Picker("Encryption", selection: $encryption) {
                    Text("Required").tag("required")
                    Text("Preferred").tag("preferred")
                    Text("Tolerated").tag("tolerated")
                }
            }

            Section {
                Button("Apply") { applyPeers() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromSession() }
        .padding()
    }

    private func loadFromSession() {
        guard let session = store.session else { return }
        globalLimit = session.peerLimitGlobal ?? 200
        perTorrentLimit = session.peerLimitPerTorrent ?? 50
        peerPort = session.peerPort ?? 51413
        portRandom = session.peerPortRandomOnStart ?? false
        portForwarding = session.portForwardingEnabled ?? false
        encryption = session.encryption ?? "preferred"
    }

    private func applyPeers() {
        Task {
            try? await store.updateSession(settings: [
                "peer-limit-global":        AnyCodable(globalLimit),
                "peer-limit-per-torrent":   AnyCodable(perTorrentLimit),
                "peer-port":                AnyCodable(peerPort),
                "peer-port-random-on-start": AnyCodable(portRandom),
                "port-forwarding-enabled":  AnyCodable(portForwarding),
                "encryption":               AnyCodable(encryption)
            ])
        }
    }
}

// MARK: - Queue Tab

struct QueueSettingsTab: View {
    @Environment(TorrentStore.self) private var store
    @State private var dlQueueEnabled = false
    @State private var dlQueueSize: Double = 5
    @State private var seedQueueEnabled = false
    @State private var seedQueueSize: Double = 5
    @State private var seedRatioEnabled = false
    @State private var seedRatio: Double = 2.0
    @State private var idleEnabled = false
    @State private var idleMinutes: Double = 30

    var body: some View {
        Form {
            Section("Download Queue") {
                Toggle("Limit simultaneous downloads", isOn: $dlQueueEnabled)
                if dlQueueEnabled {
                    Stepper("\(Int(dlQueueSize)) max downloads", value: $dlQueueSize, in: 1...20)
                }
            }

            Section("Seed Queue") {
                Toggle("Limit simultaneous seeds", isOn: $seedQueueEnabled)
                if seedQueueEnabled {
                    Stepper("\(Int(seedQueueSize)) max seeds", value: $seedQueueSize, in: 1...20)
                }
            }

            Section("Auto-stop seed") {
                Toggle("Stop when ratio reaches", isOn: $seedRatioEnabled)
                if seedRatioEnabled {
                    RatioField(label: "Ratio", value: $seedRatio)
                }

                Toggle("Stop if idle since", isOn: $idleEnabled)
                if idleEnabled {
                    Stepper("\(Int(idleMinutes)) minutes", value: $idleMinutes, in: 1...1440)
                }
            }

            Section {
                Button("Apply") { applyQueue() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear { loadFromSession() }
        .padding()
    }

    private func loadFromSession() {
        guard let session = store.session else { return }
        dlQueueEnabled = session.downloadQueueEnabled ?? false
        dlQueueSize = Double(session.downloadQueueSize ?? 5)
        seedQueueEnabled = session.seedQueueEnabled ?? false
        seedQueueSize = Double(session.seedQueueSize ?? 5)
        seedRatioEnabled = session.seedRatioLimited ?? false
        seedRatio = session.seedRatioLimit ?? 2.0
        idleEnabled = session.idleSeedingLimitEnabled ?? false
        idleMinutes = Double(session.idleSeedingLimit ?? 30)
    }

    private func applyQueue() {
        Task {
            try? await store.updateSession(settings: [
                "download-queue-enabled": AnyCodable(dlQueueEnabled),
                "download-queue-size": AnyCodable(Int(dlQueueSize)),
                "seed-queue-enabled": AnyCodable(seedQueueEnabled),
                "seed-queue-size": AnyCodable(Int(seedQueueSize)),
                "seedRatioLimited": AnyCodable(seedRatioEnabled),
                "seedRatioLimit": AnyCodable(seedRatio),
                "idle-seeding-limit-enabled": AnyCodable(idleEnabled),
                "idle-seeding-limit": AnyCodable(Int(idleMinutes))
            ])
        }
    }
}
