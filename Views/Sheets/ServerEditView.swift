import SwiftUI

struct ServerEditView: View {
    @Environment(TorrentStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var config: ServerConfig
    let isNew: Bool

    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    init(server: ServerConfig, isNew: Bool) {
        self._config = State(initialValue: server)
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "New Server" : "Edit Server")
                .font(.headline)
                .padding()

            Divider()

            Form {
                Section("General") {
                    TextField("Name", text: $config.name)
                    TextField("Host", text: $config.host)
                        .textContentType(.URL)
                    TextField("Port", value: $config.port, format: .number.grouping(.never))
                    TextField("RPC Path", text: $config.path)
                    Toggle("HTTPS", isOn: $config.useHTTPS)
                }

                Section("Authentication") {
                    TextField("Username", text: Binding(
                        get: { config.username ?? "" },
                        set: { config.username = $0.isEmpty ? nil : $0 }
                    ))
                    SecureField("Password", text: Binding(
                        get: { config.password ?? "" },
                        set: { config.password = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section {
                    HStack {
                        Text("URL")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(config.displayURL)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if let result = testResult {
                    Section {
                        switch result {
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button {
                    testConnection()
                } label: {
                    if isTesting {
                        ProgressView().scaleEffect(0.7)
                        Text("Testing…")
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting)

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Button(isNew ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(config.host.isEmpty)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func save() {
        if isNew {
            store.addServer(config)
        } else {
            store.updateServer(config)
        }
        if config.id == store.activeServerID || isNew {
            Task { await store.connect(to: config) }
        }
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let client = RPCClient(config: config)
        Task {
            do {
                try await client.testConnection()
                await MainActor.run {
                    testResult = .success(String(localized: "Connection successful!"))
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}
