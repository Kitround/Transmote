import SwiftUI
import UniformTypeIdentifiers
import CoreServices

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
        }
        return "system"
    }()
    @State private var showRestartAlert = false
    @State private var defaultAppMessage: String? = nil

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $selectedLanguage) {
                    Text("System Default").tag("system")
                    Text("English").tag("en")
                    Text("Français").tag("fr")
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

            Section("Default App") {
                HStack {
                    Text("Magnet links")
                    Spacer()
                    Button("Set as default") {
                        defaultAppMessage = setDefault(forScheme: "magnet")
                    }
                    .buttonStyle(.bordered)
                }
                HStack {
                    Text(".torrent files")
                    Spacer()
                    Button("Set as default") {
                        defaultAppMessage = setDefault(forUTI: "org.bittorrent.torrent")
                    }
                    .buttonStyle(.bordered)
                }
                if let msg = defaultAppMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.hasPrefix("✓") ? .green : .secondary)
                }
            }

            Section("Downloads") {
                HStack {
                    TextField("Download folder", text: $downloadDir)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.begin { resp in
                            guard resp == .OK, let url = panel.url else { return }
                            downloadDir = url.path
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
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                let url = Bundle.main.bundleURL
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = [url.path]
                try? task.run()
                NSApp.terminate(nil)
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Please restart Transmote to apply the language change.")
        }
        .onChange(of: downloadDir) { _, new in
            guard !new.isEmpty else { return }
            Task {
                try? await store.updateSession(settings: ["download-dir": AnyCodable(new)])
            }
        }
        .padding()
    }

    @discardableResult
    private func setDefault(forScheme scheme: String) -> String {
        guard let bundleID = Bundle.main.bundleIdentifier as CFString? else {
            return manualInstructions(for: "magnet")
        }
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleID)
        return status == noErr
            ? String(localized: "✓ Transmote is now the default app for magnet links.")
            : manualInstructions(for: "magnet")
    }

    @discardableResult
    private func setDefault(forUTI uti: String) -> String {
        guard let bundleID = Bundle.main.bundleIdentifier as CFString? else {
            return manualInstructions(for: ".torrent")
        }
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        let status = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID)
        return status == noErr
            ? String(localized: "✓ Transmote is now the default app for .torrent files.")
            : manualInstructions(for: ".torrent")
    }

    private func manualInstructions(for type: String) -> String {
        if type == "magnet" {
            return String(localized: "For magnet links: open a magnet link in Safari, then choose Transmote from the list.")
        } else {
            return String(localized: "Right-click a .torrent file → Open With → Always Open With → Transmote.")
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
                    .onChange(of: altEnabled) { _, new in
                        Task { try? await store.updateSession(settings: ["alt-speed-enabled": AnyCodable(new)]) }
                    }
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

// MARK: - Speed Field

struct SpeedField: View {
    let label: String
    @Binding var valueMB: Double
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onAppear { text = formatMB(valueMB) }
                .onSubmit { commit() }
                .onChange(of: valueMB) { _, new in text = formatMB(new) }
            Text("MB/s")
                .foregroundStyle(.secondary)
        }
    }

    private func formatMB(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(v))"
            : String(format: "%.2f", v)
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned), v > 0 {
            valueMB = v
        } else {
            text = formatMB(valueMB)
        }
    }
}

// MARK: - Ratio Field

struct RatioField: View {
    let label: String
    @Binding var value: Double
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onAppear { text = format(value) }
                .onSubmit { commit() }
                .onChange(of: value) { _, new in text = format(new) }
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private func commit() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        if let v = Double(cleaned), v >= 0 {
            value = v
        } else {
            text = format(value)
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
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Peers per torrent")
                    Spacer()
                    TextField("", value: $perTorrentLimit, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
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
