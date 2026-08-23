import SwiftUI

struct SidebarView: View {
    @Environment(TorrentStore.self) private var store
    @State private var showServerSheet = false
    @State private var editingServer: ServerConfig?

    var body: some View {
        @Bindable var store = store
        // Computed once per render — reading them inside the ForEach bodies
        // would rebuild the whole aggregate for every row.
        let filterCounts = store.filterCounts
        let folders = store.connectionState.isConnected ? store.folderCounts : []

        List(selection: $store.sidebarSelection) {
            // MARK: Filters
            Section("Filters") {
                ForEach(TorrentFilter.allCases) { filter in
                    Label {
                        HStack {
                            Text(filter.label)
                            Spacer()
                            CountBadge(count: filterCounts[filter] ?? 0)
                        }
                    } icon: {
                        Image(systemName: filter.systemImage)
                    }
                    .tag(SidebarItem.filter(filter))
                }
            }

            // MARK: Folders
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders, id: \.path) { folder in
                        Label {
                            HStack {
                                Text(URL(fileURLWithPath: folder.path).lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                CountBadge(count: folder.count)
                            }
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.folder(folder.path))
                        .help(folder.path)
                    }
                }
            }

            // MARK: Servers
            Section("Servers") {
                ForEach(store.servers) { server in
                    ServerRowView(server: server, isActive: server.id == store.activeServerID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if server.id != store.activeServerID {
                                Task { await store.connect(to: server) }
                            }
                        }
                        .contextMenu {
                            Button("Connect to server") {
                                Task { await store.connect(to: server) }
                            }
                            Button("Edit…") {
                                editingServer = server
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.removeServer(server.id)
                            }
                        }
                }

                Button {
                    showServerSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.caption)
                            .frame(width: 7, height: 7)
                        Text("Add a server")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }

            // MARK: Stats
            if store.connectionState.isConnected, let stats = store.sessionStats {
                Section("Session") {
                    VStack(alignment: .leading, spacing: 4) {
                        StatRow(label: "Downloaded", value: ByteFormatter.size(stats.currentStats.downloadedBytes))
                        StatRow(label: "Sent", value: ByteFormatter.size(stats.currentStats.uploadedBytes))
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showServerSheet) {
            ServerEditView(server: .localhost, isNew: true)
        }
        .sheet(item: $editingServer) { server in
            ServerEditView(server: server, isNew: false)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                SpeedStatusView()
                ConnectionStatusView()
            }
            .padding(8)
        }
    }
}

// MARK: - Count Badge

struct CountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(verbatim: "\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }
}

// MARK: - Server Row

struct ServerRowView: View {
    let server: ServerConfig
    let isActive: Bool
    @Environment(TorrentStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(.callout)
                    .fontWeight(isActive ? .medium : .regular)
                Text(server.host)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var indicatorColor: Color {
        guard isActive else { return .gray.opacity(0.4) }
        switch store.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }
}

// MARK: - Connection Status

struct ConnectionStatusView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            switch store.connectionState {
            case .disconnected:
                Image(systemName: "wifi.slash").foregroundStyle(.secondary)
                Text("Disconnected").foregroundStyle(.secondary)
                Spacer()
                Button("Connect") {
                    Task { await store.connectToActiveServer() }
                }
                .buttonStyle(.borderless)
                .font(.caption)

            case .connecting:
                ProgressView().scaleEffect(0.6)
                Text("Connecting…").foregroundStyle(.secondary)

            case .connected(let version):
                Circle().fill(.green).frame(width: 6, height: 6)
                Text(version)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()

            case .error(let msg):
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                Text(msg)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .font(.caption)
                Spacer()
                Button("Retry") {
                    Task { await store.connectToActiveServer() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .font(.caption)
        .padding(6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Speed Status

struct SpeedStatusView: View {
    @Environment(TorrentStore.self) private var store

    var body: some View {
        if store.connectionState.isConnected {
            let down = store.totalDownloadSpeed
            let up = store.totalUploadSpeed
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.blue)
                    Text(ByteFormatter.transferRate(down))
                        .monospacedDigit()
                        .foregroundStyle(down > 0 ? .primary : .secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.green)
                    Text(ByteFormatter.transferRate(up))
                        .monospacedDigit()
                        .foregroundStyle(up > 0 ? .primary : .secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
