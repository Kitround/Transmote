import Foundation

// MARK: - Response types

nonisolated struct TorrentGetArguments: Decodable, Sendable {
    let torrents: [Torrent]
}

nonisolated struct TorrentAddArguments: Decodable, Sendable {
    let torrentAdded: AddedTorrent?
    let torrentDuplicate: AddedTorrent?

    enum CodingKeys: String, CodingKey {
        case torrentAdded = "torrent-added"
        case torrentDuplicate = "torrent-duplicate"
    }
}

nonisolated struct AddedTorrent: Decodable, Sendable {
    let id: Int
    let name: String
    let hashString: String
}

// MARK: - Fields constants

/// Light fields fetched for every torrent on each poll cycle.
private nonisolated let kListFields: [String] = [
    "id", "name", "status", "totalSize", "downloadedEver", "uploadedEver",
    "rateDownload", "rateUpload", "eta", "percentDone", "uploadRatio",
    "peersConnected", "peersSendingToUs", "peersGettingFromUs",
    "addedDate", "doneDate", "downloadDir", "error", "errorString",
    "hashString", "comment", "isPrivate", "isFinished",
    "recheckProgress", "sizeWhenDone", "leftUntilDone"
]

/// Heavy fields fetched only for the selected torrent (detail panel).
private nonisolated let kDetailFields: [String] = kListFields + [
    "trackerStats", "files", "fileStats", "peers"
]

// MARK: - RPCClient methods

extension RPCClient {

    // MARK: Torrent-get

    func getTorrents() async throws -> [Torrent] {
        let args: [String: AnyCodable] = ["fields": AnyCodable(kListFields)]
        let r: RPCResponse<TorrentGetArguments> = try await request(
            method: "torrent-get", arguments: args, responseType: TorrentGetArguments.self)
        guard r.isSuccess, let body = r.arguments else { throw RPCError.serverError(r.result) }
        return body.torrents
    }

    func getTorrentDetail(id: Int) async throws -> Torrent? {
        let args: [String: AnyCodable] = [
            "fields": AnyCodable(kDetailFields),
            "ids":    AnyCodable([id])
        ]
        let r: RPCResponse<TorrentGetArguments> = try await request(
            method: "torrent-get", arguments: args, responseType: TorrentGetArguments.self)
        return r.arguments?.torrents.first
    }

    // MARK: Actions

    func startTorrents(ids: [Int]) async throws      { try await action("torrent-start",      ids: ids) }
    func stopTorrents(ids: [Int]) async throws       { try await action("torrent-stop",       ids: ids) }
    func verifyTorrents(ids: [Int]) async throws     { try await action("torrent-verify",     ids: ids) }
    func reannounceTorrents(ids: [Int]) async throws { try await action("torrent-reannounce", ids: ids) }

    /// Omitting "ids" makes Transmission apply the action to every torrent.
    private func action(_ method: String, ids: [Int]?) async throws {
        let args = ids.map { ["ids": AnyCodable($0)] }
        let r: RPCResponse<EmptyArguments> = try await request(
            method: method, arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func startAllTorrents() async throws { try await action("torrent-start", ids: nil) }
    func stopAllTorrents() async throws  { try await action("torrent-stop",  ids: nil) }

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

    func addTorrentFile(_ base64: String) async throws -> AddedTorrent {
        try await addTorrent(arguments: ["metainfo": AnyCodable(base64)])
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

    func setTorrentLocation(ids: [Int], location: String, move: Bool) async throws {
        let args: [String: AnyCodable] = [
            "ids":      AnyCodable(ids),
            "location": AnyCodable(location),
            "move":     AnyCodable(move)
        ]
        let r: RPCResponse<EmptyArguments> = try await request(
            method: "torrent-set-location", arguments: args, responseType: EmptyArguments.self)
        guard r.isSuccess else { throw RPCError.serverError(r.result) }
    }

    func setTorrentPriority(id: Int, fileIndices: [Int], priority: FilePriority) async throws {
        var args: [String: AnyCodable] = ["ids": AnyCodable([id])]
        switch priority {
        case .skip:
            args["files-unwanted"] = AnyCodable(fileIndices)
        case .low, .normal, .high:
            // A file set to a real priority must also be marked wanted —
            // it may have been skipped (unwanted) before. Send both keys
            // in the same torrent-set so the file is re-enabled and
            // prioritised at once.
            args["files-wanted"] = AnyCodable(fileIndices)
            let priorityKey = priority == .low ? "priority-low"
                            : priority == .high ? "priority-high"
                            : "priority-normal"
            args[priorityKey] = AnyCodable(fileIndices)
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
}
