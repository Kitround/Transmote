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
}

// MARK: - Store

@MainActor
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
    var isWindowVisible: Bool = true
    var isAppActive: Bool = true

    var pollingInterval: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: "pollingInterval")
            return stored.isZero ? 3 : stored
        }
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

    /// Dossiers uniques triés + nombre de torrents, en une seule passe.
    var folderCounts: [(path: String, count: Int)] {
        torrents
            .reduce(into: [String: Int]()) { $0[$1.downloadDir, default: 0] += 1 }
            .map { (path: $0.key, count: $0.value) }
            .sorted { $0.path < $1.path }
    }

    /// Le torrent a-t-il atteint le ratio de partage configuré côté serveur ?
    func hasReachedSeedRatio(_ torrent: Torrent) -> Bool {
        guard session?.seedRatioLimited == true, let limit = session?.seedRatioLimit else { return false }
        return torrent.uploadRatio >= limit
    }

    var totalDownloadSpeed: Int { torrents.reduce(0) { $0 + $1.rateDownload } }
    var totalUploadSpeed: Int { torrents.reduce(0) { $0 + $1.rateUpload } }

    var activeServer: ServerConfig? {
        servers.first { $0.id == activeServerID }
    }

    // MARK: - Connection

    func connect(to server: ServerConfig) async {
        stopPolling()
        connectionState = .connecting
        let rpc = RPCClient(config: server)
        client = rpc
        activeServerID = server.id

        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Double(attempt)))
            }
            do {
                let session = try await rpc.getSession()
                // Bail out if a newer connect()/disconnect() superseded us
                // while awaiting, so we don't resurrect a stale connection.
                guard client === rpc else { return }
                self.session = session
                isAltSpeedEnabled = session.altSpeedEnabled ?? false
                connectionState = .connected(version: session.version ?? "?")
                startPolling()
                return
            } catch {
                guard client === rpc else { return }
                if case .authenticationFailed = error as? RPCError {
                    connectionState = .error(String(localized: "Authentication failed"))
                    client = nil
                    return
                }
                lastError = error
            }
        }
        guard client === rpc else { return }
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
        isAltSpeedEnabled = false
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let visible = self.isWindowVisible
                let active  = self.isAppActive
                // Always full fetch so completion notifications still fire when hidden.
                await self.fetchAll()
                let interval: TimeInterval
                switch (visible, active) {
                case (true,  true):  interval = self.pollingInterval               // foreground
                case (true,  false): interval = max(self.pollingInterval * 3, 10)  // visible but not focused
                case (false, _):     interval = max(self.pollingInterval * 5, 15)  // hidden/minimized
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func fetchAll() async {
        async let t: () = refreshTorrents()
        async let s: () = fetchStats()
        _ = await (t, s)
    }

    private func refreshTorrents() async {
        guard let client else { return }
        let selectedID = selectedTorrentIDs.first
        async let listTask = client.getTorrents()
        async let detailTask = fetchDetailIfNeeded(id: selectedID, using: client)
        do {
            var torrents = try await listTask
            if let detail = await detailTask,
               let idx = torrents.firstIndex(where: { $0.id == detail.id }) {
                torrents[idx].files         = detail.files
                torrents[idx].fileStats     = detail.fileStats
                torrents[idx].peers         = detail.peers
                torrents[idx].trackerStats  = detail.trackerStats
            }
            detectCompletions(new: torrents)
            applyDiff(newTorrents: torrents, selectedID: selectedID)
            let activeIDs = Set(torrents.map(\.id))
            previousStatuses = previousStatuses.filter { activeIDs.contains($0.key) }
        } catch {
            if case .authenticationFailed = error as? RPCError {
                connectionState = .error(String(localized: "Authentication failed"))
                stopPolling()
            }
        }
    }

    func refresh() async { await refreshTorrents() }

    /// Replace the torrent list with the fresh snapshot, stripping heavy
    /// detail fields (files/fileStats/peers/trackerStats) from every
    /// row except the one whose detail was fetched this cycle. Keeps memory
    /// bounded no matter how many torrents the user has selected over time.
    private func applyDiff(newTorrents: [Torrent], selectedID: Int?) {
        var result = newTorrents
        for i in result.indices where result[i].id != selectedID {
            result[i].files = nil; result[i].fileStats = nil
            result[i].peers = nil; result[i].trackerStats = nil
        }
        torrents = result
    }

    private func fetchDetailIfNeeded(id: Int?, using client: RPCClient) async -> Torrent? {
        guard let id else { return nil }
        return try? await client.getTorrentDetail(id: id)
    }

    func fetchStats() async {
        guard let client else { return }
        do {
            let stats = try await client.getSessionStats()
            sessionStats = stats
            (NSApp.delegate as? AppDelegate)?.updateStatusBarTitle(
                download: stats.downloadSpeed,
                upload: stats.uploadSpeed
            )
        } catch {}
    }

    private func detectCompletions(new: [Torrent]) {
        for torrent in new {
            let prev = previousStatuses[torrent.id]
            if let prev = prev, prev.isDownloading, torrent.status.isSeeding,
               torrent.isFinished || torrent.percentDone >= 1 {
                (NSApp.delegate as? AppDelegate)?.notifyTorrentComplete(name: torrent.name)
            }
            previousStatuses[torrent.id] = torrent.status
        }
    }

    // MARK: - Actions

    func start(ids: [Int]) async {
        guard let client else { return }
        try? await client.startTorrents(ids: ids)
        await refreshTorrents()
    }

    func stop(ids: [Int]) async {
        guard let client else { return }
        try? await client.stopTorrents(ids: ids)
        await refreshTorrents()
    }

    func verify(ids: [Int]) async {
        guard let client else { return }
        try? await client.verifyTorrents(ids: ids)
        await refreshTorrents()
    }

    func reannounce(ids: [Int]) async {
        guard let client else { return }
        try? await client.reannounceTorrents(ids: ids)
    }

    func remove(ids: [Int], deleteData: Bool) async {
        guard let client else { return }
        try? await client.removeTorrents(ids: ids, deleteData: deleteData)
        selectedTorrentIDs.subtract(ids)
        torrents.removeAll { ids.contains($0.id) }
    }

    func addMagnet(_ magnetURL: String) async throws -> AddedTorrent {
        guard let client else { throw RPCError.notConnected }
        let result = try await client.addTorrentMagnet(magnetURL)
        await refreshTorrents()
        return result
    }

    func addFile(at url: URL) async throws -> AddedTorrent {
        guard let client else { throw RPCError.notConnected }
        let data = try Data(contentsOf: url)
        let base64 = data.base64EncodedString()
        let result = try await client.addTorrentFile(base64)
        await refreshTorrents()
        return result
    }

    func startAll() async {
        guard let client else { return }
        try? await client.startAllTorrents()
        await refreshTorrents()
    }

    func stopAll() async {
        guard let client else { return }
        try? await client.stopAllTorrents()
        await refreshTorrents()
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
        await refreshTorrents()
    }

    func refreshSession() async {
        guard let client else { return }
        if let session = try? await client.getSession() {
            self.session = session
            isAltSpeedEnabled = session.altSpeedEnabled ?? false
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
        KeychainStore.deletePassword(for: id)
        if activeServerID == id {
            activeServerID = servers.first?.id
            disconnect()
        }
        saveServers()
    }

    private func saveServers() {
        // Passwords live in the Keychain only; strip them before persisting.
        for server in servers {
            KeychainStore.setPassword(server.password, for: server.id)
        }
        var sanitized = servers
        for i in sanitized.indices { sanitized[i].password = nil }
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: "servers")
        }
    }

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: "servers"),
              var loaded = try? JSONDecoder().decode([ServerConfig].self, from: data)
        else { return }
        // Migrate legacy plaintext passwords from UserDefaults to the Keychain.
        var needsMigration = false
        for i in loaded.indices {
            if let legacy = loaded[i].password, !legacy.isEmpty {
                KeychainStore.setPassword(legacy, for: loaded[i].id)
                needsMigration = true
            } else {
                loaded[i].password = KeychainStore.password(for: loaded[i].id)
            }
        }
        servers = loaded
        if needsMigration { saveServers() }
    }

    // MARK: - Folder management

    func moveTorrents(_ ids: [Int], toDirectory path: String) async {
        guard let client else { return }
        try? await client.setTorrentLocation(ids: ids, location: path, move: true)
        await refreshTorrents()
    }
}
