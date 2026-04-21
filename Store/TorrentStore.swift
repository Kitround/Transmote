import SwiftUI

// MARK: - Connection State

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(version: String)
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var displayString: String {
        switch self {
        case .disconnected:     return String(localized: "Disconnected")
        case .connecting:       return String(localized: "Connecting…")
        case .connected(let v): return "Transmission \(v)"
        case .error(let msg):   return String(localized: "Error: \(msg)")
        }
    }
}

// MARK: - Store

@Observable
class TorrentStore {
    // MARK: State
    var torrents: [Torrent] = []
    var selectedTorrentIDs: Set<Int> = []
    var sidebarSelection: SidebarItem = .filter(.all)
    var searchText: String = ""
    var sortOrder: TorrentSortOrder = .addedDate
    var sortAscending: Bool = false
    var connectionState: ConnectionState = .disconnected
    var session: SessionArguments?
    var sessionStats: SessionStats?
    var servers: [ServerConfig] = []
    var activeServerID: UUID?
    var isAltSpeedEnabled: Bool = false

    var pollingInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: "pollingInterval").isZero ? 3 : UserDefaults.standard.double(forKey: "pollingInterval") }
        set { UserDefaults.standard.set(newValue, forKey: "pollingInterval") }
    }

    // MARK: Private
    private var client: RPCClient?
    private var pollingTask: Task<Void, Never>?
    private var previousStatuses: [Int: TorrentStatus] = [:]

    // MARK: Init
    init() {
        loadServers()
        if let first = servers.first {
            activeServerID = first.id
        } else {
            servers = [.localhost]
            activeServerID = servers[0].id
            saveServers()
        }
    }

    // MARK: - Computed

    var filteredTorrents: [Torrent] {
        var result = torrents

        switch sidebarSelection {
        case .filter(let f):
            if f != .all { result = result.filter { f.matches($0) } }
        case .folder(let path):
            result = result.filter { $0.downloadDir == path }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }

        result.sort { sortAscending ? sortOrder.compare($1, $0) : sortOrder.compare($0, $1) }
        return result
    }

    var selectedTorrents: [Torrent] {
        torrents.filter { selectedTorrentIDs.contains($0.id) }
    }

    var firstSelectedTorrent: Torrent? {
        guard let id = selectedTorrentIDs.first else { return nil }
        return torrents.first { $0.id == id }
    }

    var filterCounts: [TorrentFilter: Int] {
        var counts: [TorrentFilter: Int] = [.all: torrents.count]
        for torrent in torrents {
            for filter in TorrentFilter.allCases where filter != .all && filter.matches(torrent) {
                counts[filter, default: 0] += 1
            }
        }
        return counts
    }

    /// Dossiers uniques triés, déduits des torrents courants
    var downloadDirs: [String] {
        Array(Set(torrents.map(\.downloadDir))).sorted()
    }

    func folderCount(for path: String) -> Int {
        torrents.filter { $0.downloadDir == path }.count
    }

    var totalDownloadSpeed: Int { torrents.reduce(0) { $0 + $1.rateDownload } }
    var totalUploadSpeed: Int { torrents.reduce(0) { $0 + $1.rateUpload } }

    var activeServer: ServerConfig? {
        servers.first { $0.id == activeServerID }
    }

    // MARK: - Grouped torrents (vue compacte)

    /// Torrents par dossier, triés par chemin.
    func torrentsByFolder(from source: [Torrent]) -> [(path: String, torrents: [Torrent])] {
        let dirs = Array(Set(source.map(\.downloadDir))).sorted()
        return dirs.map { path in
            (path: path, torrents: source.filter { $0.downloadDir == path })
        }
    }

    // MARK: - Connection

    func connect(to server: ServerConfig) async {
        stopPolling()
        connectionState = .connecting
        client = RPCClient(config: server)
        activeServerID = server.id

        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Double(attempt)))
            }
            do {
                let session = try await client!.getSession()
                self.session = session
                isAltSpeedEnabled = session.altSpeedEnabled ?? false
                connectionState = .connected(version: session.version ?? "?")
                startPolling()
                return
            } catch {
                if case .authenticationFailed = error as? RPCError {
                    connectionState = .error(String(localized: "Authentication failed"))
                    client = nil
                    return
                }
                lastError = error
            }
        }
        connectionState = .error(lastError?.localizedDescription ?? "Unknown error")
        client = nil
    }

    func connectToActiveServer() async {
        guard let server = activeServer else { return }
        switch connectionState {
        case .connecting, .connected: return
        default: break
        }
        await connect(to: server)
    }

    func disconnect() {
        stopPolling()
        client = nil
        torrents = []
        session = nil
        sessionStats = nil
        connectionState = .disconnected
        previousStatuses = [:]
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.fetchAll()
                try? await Task.sleep(for: .seconds(self.pollingInterval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func fetchAll() async {
        async let t: () = fetchTorrents()
        async let s: () = fetchStats()
        _ = await (t, s)
    }

    func fetchTorrents() async {
        guard let client else { return }
        do {
            let fetched = try await client.getTorrents()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.detectCompletions(new: fetched)
                self.torrents = fetched
            }
        } catch {
            if case .authenticationFailed = error as? RPCError {
                await MainActor.run {
                    self.connectionState = .error(String(localized: "Authentication failed"))
                    self.stopPolling()
                }
            }
        }
    }

    func fetchStats() async {
        guard let client else { return }
        do {
            let stats = try await client.getSessionStats()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.sessionStats = stats
                (NSApp.delegate as? AppDelegate)?.updateStatusBarTitle(
                    download: stats.downloadSpeed,
                    upload: stats.uploadSpeed
                )
            }
        } catch {}
    }

    private func detectCompletions(new: [Torrent]) {
        for torrent in new {
            let prev = previousStatuses[torrent.id]
            if let prev = prev, prev.isDownloading && torrent.status.isSeeding {
                (NSApp.delegate as? AppDelegate)?.notifyTorrentComplete(name: torrent.name)
            }
            previousStatuses[torrent.id] = torrent.status
        }
    }

    // MARK: - Actions

    func start(ids: [Int]) async {
        guard let client else { return }
        try? await client.startTorrents(ids: ids)
        await fetchTorrents()
    }

    func stop(ids: [Int]) async {
        guard let client else { return }
        try? await client.stopTorrents(ids: ids)
        await fetchTorrents()
    }

    func verify(ids: [Int]) async {
        guard let client else { return }
        try? await client.verifyTorrents(ids: ids)
        await fetchTorrents()
    }

    func reannounce(ids: [Int]) async {
        guard let client else { return }
        try? await client.reannounceTorrents(ids: ids)
    }

    func remove(ids: [Int], deleteData: Bool) async {
        guard let client else { return }
        try? await client.removeTorrents(ids: ids, deleteData: deleteData)
        await MainActor.run {
            selectedTorrentIDs.subtract(ids)
            torrents.removeAll { ids.contains($0.id) }
        }
    }

    func addMagnet(_ magnetURL: String) async throws -> AddedTorrent {
        guard let client else { throw RPCError.notConnected }
        let result = try await client.addTorrentMagnet(magnetURL)
        await fetchTorrents()
        return result
    }

    func addFile(at url: URL) async throws -> AddedTorrent {
        guard let client else { throw RPCError.notConnected }
        let data = try Data(contentsOf: url)
        let base64 = data.base64EncodedString()
        let result = try await client.addTorrentFile(base64)
        await fetchTorrents()
        return result
    }

    func startAll() async {
        guard let client else { return }
        try? await client.startAllTorrents()
        await fetchTorrents()
    }

    func stopAll() async {
        guard let client else { return }
        try? await client.stopAllTorrents()
        await fetchTorrents()
    }

    func toggleAltSpeed() async {
        guard let client else { return }
        let newValue = !isAltSpeedEnabled
        try? await client.setAlternativeSpeedEnabled(newValue)
        isAltSpeedEnabled = newValue
    }

    func setFilePriority(torrentID: Int, fileIndex: Int, priority: FilePriority) async {
        guard let client else { return }
        try? await client.setTorrentPriority(id: torrentID, fileIndices: [fileIndex], priority: priority)
        await fetchTorrents()
    }

    func refreshSession() async {
        guard let client else { return }
        if let session = try? await client.getSession() {
            await MainActor.run { self.session = session }
        }
    }

    func updateSession(settings: [String: AnyCodable]) async throws {
        guard let client else { throw RPCError.notConnected }
        try await client.setSession(settings)
        await refreshSession()
    }

    // MARK: - Server management

    func addServer(_ config: ServerConfig) {
        servers.append(config)
        saveServers()
    }

    func updateServer(_ config: ServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == config.id }) {
            servers[idx] = config
            saveServers()
        }
    }

    func removeServer(_ id: UUID) {
        servers.removeAll { $0.id == id }
        if activeServerID == id {
            activeServerID = servers.first?.id
            disconnect()
        }
        saveServers()
    }

    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: "servers")
        }
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: "servers"),
              let loaded = try? JSONDecoder().decode([ServerConfig].self, from: data)
        else { return }
        servers = loaded
    }

    // MARK: - Folder management

    func moveTorrents(_ ids: [Int], toDirectory path: String) async {
        guard let client else { return }
        for id in ids {
            try? await client.setTorrentLocation(id: id, location: path, move: true)
        }
        await fetchTorrents()
    }
}
