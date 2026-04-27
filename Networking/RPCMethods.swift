import Foundation

// MARK: - Response types

struct TorrentGetArguments: Decodable, Sendable {
    let torrents: [Torrent]

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        torrents = try c.decode([Torrent].self, forKey: .torrents)
    }

    enum CodingKeys: String, CodingKey { case torrents }
}

struct TorrentAddArguments: Decodable, Sendable {
    let torrentAdded: AddedTorrent?
    let torrentDuplicate: AddedTorrent?

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        torrentAdded      = try c.decodeIfPresent(AddedTorrent.self, forKey: .torrentAdded)
        torrentDuplicate  = try c.decodeIfPresent(AddedTorrent.self, forKey: .torrentDuplicate)
    }

    enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent-added"
        case torrentDuplicate = "torrent-duplicate"
    }
}

struct AddedTorrent: Decodable, Sendable {
    let id: Int
    let name: String
    let hashString: String

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(Int.self,    forKey: .id)
        name       = try c.decode(String.self, forKey: .name)
        hashString = try c.decode(String.self, forKey: .hashString)
    }

    enum CodingKeys: String, CodingKey { case id, name, hashString }
}

struct FreeSpaceArguments: Decodable, Sendable {
    let path: String
    let sizeBytes: Int64

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path      = try c.decode(String.self, forKey: .path)
        sizeBytes = try c.decode(Int64.self,  forKey: .sizeBytes)
    }

    enum CodingKeys: String, CodingKey {
        case path
        case sizeBytes = "size-bytes"
    }
}


// MARK: - Fields constant

private nonisolated let kFields: [String] = [
    "id", "name", "status", "totalSize", "downloadedEver", "uploadedEver",
    "rateDownload", "rateUpload", "eta", "percentDone", "uploadRatio",
    "peersConnected", "peersSendingToUs", "peersGettingFromUs",
    "addedDate", "doneDate", "downloadDir", "error", "errorString",
    "hashString", "comment", "isPrivate", "isFinished", "queuePosition",
    "recheckProgress", "sizeWhenDone", "leftUntilDone", "activityDate",
    "trackerStats", "files", "fileStats", "peers", "wanted", "priorities"
]

// MARK: - RPCClient methods

extension RPCClient {

    // MARK: Torrent-get

    func getTorrents() async throws -> [Torrent] {
        let args: [String: AnyCodable] = ["fields": AnyCodable(kFields)]
        let r: RPCResponse<TorrentGetArguments> = try await request(
            method: "torrent-get", arguments: args, responseType: TorrentGetArguments.self)
        guard r.isSuccess, let body = r.arguments else { throw RPCError.serverError(r.result) }
        return body.torrents
    }

    func getTorrent(id: Int) async throws -> Torrent? {
        let args: [String: AnyCodable] = [
            "fields": AnyCodable(kFields),
            "ids":    AnyCodable([id])
        ]
        let r: RPCResponse<TorrentGetArguments> = try await request(
            method: "torrent-get", arguments: args, responseType: TorrentGetArguments.self)
        return r.arguments?.torrents.first
    }

    // MARK: Actions

    func startTorrents(ids: [Int]) async throws      { try await action("torrent-start",      ids: ids) }
    func startTorrentsNow(ids: [Int]) async throws   { try await action("torrent-start-now",  ids: ids) }
    func stopTorrents(ids: [Int]) async throws       { try await action("torrent-stop",       ids: ids) }
    func verifyTorrents(ids: [Int]) async throws     { try await action("torrent-verify",     ids: ids) }
    func reannounceTorrents(ids: [Int]) async throws { try await action("torrent-reannounce", ids: ids) }

    private func action(_ method: String, ids: [Int]) async throws {
        let args: [String: AnyCodable] = ["ids": AnyCodable(ids)]
        let r: RPCResponse<EmptyArguments> = try await request(
            method: method, arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func startAllTorrents() async throws {
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-start", responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func stopAllTorrents() async throws {
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-stop", responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    // MARK: Remove

    func removeTorrents(ids: [Int], deleteData: Bool) async throws {
        let args: [String: AnyCodable] = [
            "ids":               AnyCodable(ids),
            "delete-local-data": AnyCodable(deleteData)
        ]
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-remove", arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    // MARK: Add

    func addTorrentMagnet(_ url: String) async throws -> AddedTorrent {
        try await addTorrent(arguments: ["filename": AnyCodable(url)])
    }

    func addTorrentFile(_ base64: String, downloadDir: String? = nil) async throws -> AddedTorrent {
        var args: [String: AnyCodable] = ["metainfo": AnyCodable(base64)]
        if let dir = downloadDir { args["download-dir"] = AnyCodable(dir) }
        return try await addTorrent(arguments: args)
    }

    func addTorrentURL(_ urlString: String) async throws -> AddedTorrent {
        try await addTorrent(arguments: ["filename": AnyCodable(urlString)])
    }

    private func addTorrent(arguments: [String: AnyCodable]) async throws -> AddedTorrent {
        let r: RPCResponse<TorrentAddArguments> = try await request(
            method: "torrent-add", arguments: arguments, responseType: TorrentAddArguments.self)
        guard r.isSuccess, let body = r.arguments else { throw RPCError.serverError(r.result) }
        if let t = body.torrentAdded     { return t }
        if let t = body.torrentDuplicate { return t }
        throw RPCError.serverError("No torrent returned")
    }

    // MARK: Torrent-set

    func setTorrentLocation(id: Int, location: String, move: Bool) async throws {
        let args: [String: AnyCodable] = [
            "ids":      AnyCodable([id]),
            "location": AnyCodable(location),
            "move":     AnyCodable(move)
        ]
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-set-location", arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func setTorrentPriority(id: Int, fileIndices: [Int], priority: FilePriority) async throws {
        let key: String
        switch priority {
        case .low:    key = "priority-low"
        case .normal: key = "priority-normal"
        case .high:   key = "priority-high"
        case .skip:   key = "files-unwanted"
        }
        let args: [String: AnyCodable] = ["ids": AnyCodable([id]), key: AnyCodable(fileIndices)]
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-set", arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func setSpeedLimit(id: Int, downloadLimit: Int?, uploadLimit: Int?) async throws {
        var args: [String: AnyCodable] = ["ids": AnyCodable([id])]
        if let dl = downloadLimit {
            args["downloadLimit"]   = AnyCodable(dl)
            args["downloadLimited"] = AnyCodable(true)
        }
        if let ul = uploadLimit {
            args["uploadLimit"]   = AnyCodable(ul)
            args["uploadLimited"] = AnyCodable(true)
        }
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-set", arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    // MARK: Session

    func getSession() async throws -> SessionArguments {
        let r: RPCResponse<SessionArguments> = try await request(
            method: "session-get", responseType: SessionArguments.self)
        guard r.isSuccess, let body = r.arguments else { throw RPCError.serverError(r.result) }
        return body
    }

    func setSession(_ settings: [String: AnyCodable]) async throws {
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "session-set", arguments: settings, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func getSessionStats() async throws -> SessionStats {
        let r: RPCResponse<SessionStats> = try await request(
            method: "session-stats", responseType: SessionStats.self)
        guard r.isSuccess, let body = r.arguments else { throw RPCError.serverError(r.result) }
        return body
    }

    func setAlternativeSpeedEnabled(_ enabled: Bool) async throws {
        try await setSession(["alt-speed-enabled": AnyCodable(enabled)])
    }

    func setGlobalDownloadLimit(_ kbps: Int, enabled: Bool) async throws {
        try await setSession([
            "speed-limit-down":         AnyCodable(kbps),
            "speed-limit-down-enabled": AnyCodable(enabled)
        ])
    }

    func setGlobalUploadLimit(_ kbps: Int, enabled: Bool) async throws {
        try await setSession([
            "speed-limit-up":         AnyCodable(kbps),
            "speed-limit-up-enabled": AnyCodable(enabled)
        ])
    }

    func freeSpace(path: String) async throws -> Int64 {
        let r: RPCResponse<FreeSpaceArguments> = try await request(
            method: "free-space", arguments: ["path": AnyCodable(path)],
            responseType: FreeSpaceArguments.self)
        return r.arguments?.sizeBytes ?? 0
    }

}
