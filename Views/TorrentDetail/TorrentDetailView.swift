import SwiftUI

struct TorrentDetailView: View {
    @Environment(TorrentStore.self) private var store
    @State private var selectedTab: DetailTab = .info

    enum DetailTab: String, CaseIterable {
        case info = "Info"
        case files = "Files"
        case peers = "Peers"
        case trackers = "Trackers"
    }

    var body: some View {
        if let torrent = store.firstSelectedTorrent {
            VStack(spacing: 0) {
                // Header
                DetailHeaderView(torrent: torrent)
                    .padding()

                Divider()

                // Tab bar
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Content
                ScrollView {
                    switch selectedTab {
                    case .info:
                        DetailInfoView(torrent: torrent)
                    case .files:
                        DetailFilesView(torrent: torrent)
                    case .peers:
                        DetailPeersView(torrent: torrent)
                    case .trackers:
                        DetailTrackersView(torrent: torrent)
                    }
                }
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "arrow.left.square", description: Text("Select a torrent to view its details."))
        }
    }
}

// MARK: - Header

struct DetailHeaderView: View {
    let torrent: Torrent
    @Environment(TorrentStore.self) private var store
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(torrent.name)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(progressColor)
                            .frame(width: geo.size.width * torrent.progress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(ProgressFormatter.format(torrent.progress))
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    if torrent.eta >= 0 {
                        Text("ETA \(torrent.etaDuration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                if torrent.status.isStopped || torrent.status == .checkWait || torrent.status == .downloadWait || torrent.status == .seedWait {
                    Button {
                        Task { await store.start(ids: [torrent.id]) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                } else {
                    Button {
                        Task { await store.stop(ids: [torrent.id]) }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: torrent.downloadDir)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .help("Reveal in Finder")

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("Remove torrent")
                .confirmationDialog("Remove \"\(torrent.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Remove Torrent", role: .destructive) {
                        Task { await store.remove(ids: [torrent.id], deleteData: false) }
                    }
                    Button("Remove and Delete Data", role: .destructive) {
                        Task { await store.remove(ids: [torrent.id], deleteData: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    private var progressColor: Color {
        if torrent.hasError { return .red }
        switch torrent.status {
        case .download, .downloadWait: return .blue
        case .seed, .seedWait: return .green
        default: return .secondary
        }
    }
}

// MARK: - Info Tab

struct DetailInfoView: View {
    @Environment(TorrentStore.self) private var store
    let torrent: Torrent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailSection("Transfer") {
                InfoRow(label: "↓ Download", value: ByteFormatter.transferRate(torrent.rateDownload), color: torrent.rateDownload > 0 ? .blue : nil)
                InfoRow(label: "↑ Upload", value: ByteFormatter.transferRate(torrent.rateUpload), color: torrent.rateUpload > 0 ? .green : nil)
                InfoRow(label: "Downloaded", value: ByteFormatter.size(torrent.downloadedEver))
                InfoRow(label: "Sent", value: ByteFormatter.size(torrent.uploadedEver))
                InfoRow(label: "Ratio", value: RatioFormatter.format(torrent.uploadRatio), color: ratioColor)
            }

            DetailSection("File") {
                InfoRow(label: "Size", value: ByteFormatter.size(torrent.sizeWhenDone))
                InfoRow(label: "Remaining", value: ByteFormatter.size(torrent.leftUntilDone))
                InfoRow(label: "Folder", value: torrent.downloadDir)
            }

            DetailSection("Peers") {
                InfoRow(label: "Connected Peers", value: "\(torrent.peersConnected)")
                InfoRow(label: "Downloading from", value: "\(torrent.peersSendingToUs)")
                InfoRow(label: "Uploading to", value: "\(torrent.peersGettingFromUs)")
            }

            DetailSection("Dates") {
                InfoRow(label: "Added", value: torrent.addedDateFormatted)
                if let done = torrent.doneDateFormatted {
                    InfoRow(label: "Completed", value: done)
                }
            }

            DetailSection("Information") {
                InfoRow(label: "Hash", value: torrent.hashString, mono: true, copyable: true)
                if let comment = torrent.comment, !comment.isEmpty {
                    InfoRow(label: "Comment", value: comment)
                }
                InfoRow(label: "Private", value: torrent.isPrivate ? String(localized: "Yes") : String(localized: "No"))
                InfoRow(label: "Status", value: torrent.status.description)
                if torrent.hasError {
                    InfoRow(label: "Error", value: torrent.errorString, color: .red)
                }
            }
        }
        .padding()
    }

    private var ratioColor: Color? {
        guard store.session?.seedRatioLimited == true,
              let limit = store.session?.seedRatioLimit,
              torrent.uploadRatio >= limit else { return nil }
        return .green
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 6)

            content
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String
    var color: Color? = nil
    var mono: Bool = false
    var copyable: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Text(value)
                        .font(mono ? .caption.monospaced() : .callout)
                        .foregroundStyle(color ?? .primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .help("Click to copy")
            } else {
                Text(value)
                    .font(mono ? .caption.monospaced() : .callout)
                    .foregroundStyle(color ?? .primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Files Tab

struct DetailFilesView: View {
    let torrent: Torrent
    @Environment(TorrentStore.self) private var store

    var body: some View {
        if let files = torrent.filesWithStats, !files.isEmpty {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(files, id: \.index) { item in
                    FileRowView(
                        file: item.file,
                        stat: item.stat,
                        index: item.index,
                        torrentID: torrent.id
                    )
                    Divider()
                }
            }
        } else {
            Text("No file information available")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

struct FileRowView: View {
    let file: TorrentFile
    let stat: TorrentFileStat
    let index: Int
    let torrentID: Int
    @Environment(TorrentStore.self) private var store
    @State private var showPriorityMenu = false

    var priority: FilePriority {
        guard stat.wanted else { return .skip }
        return FilePriority(rawValue: stat.priority) ?? .normal
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Wanted toggle
            Image(systemName: stat.wanted ? "checkmark.square" : "square")
                .foregroundStyle(stat.wanted ? .blue : .secondary)
                .onTapGesture {
                    let newPriority: FilePriority = stat.wanted ? .skip : .normal
                    Task { await store.setFilePriority(torrentID: torrentID, fileIndex: index, priority: newPriority) }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name.split(separator: "/").last.map(String.init) ?? file.name)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(stat.wanted ? .primary : .secondary)

                HStack(spacing: 6) {
                    // Mini progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary).frame(height: 3)
                            Capsule().fill(priorityColor).frame(width: geo.size.width * file.progress, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .frame(maxWidth: 80)

                    Text(ProgressFormatter.format(file.progress))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormatter.size(file.length))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Menu {
                    ForEach([FilePriority.high, .normal, .low, .skip], id: \.rawValue) { p in
                        Button {
                            Task { await store.setFilePriority(torrentID: torrentID, fileIndex: index, priority: p) }
                        } label: {
                            Label(p.description, systemImage: priority == p ? "checkmark" : "")
                        }
                    }
                } label: {
                    Text(priority.description)
                        .font(.caption2)
                        .foregroundStyle(priorityColor)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var priorityColor: Color {
        switch priority {
        case .high: return .orange
        case .normal: return .blue
        case .low: return .gray
        case .skip: return .secondary
        }
    }
}

// MARK: - Peers Tab

struct DetailPeersView: View {
    let torrent: Torrent

    var body: some View {
        if let peers = torrent.peers, !peers.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(peers) { peer in
                    PeerRowView(peer: peer)
                    Divider()
                }
            }
        } else {
            Text("No peers connected")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

struct PeerRowView: View {
    let peer: Peer

    var body: some View {
        HStack(spacing: 10) {
            Text("🌐")
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text(peer.clientName.isEmpty ? String(localized: "Unknown client") : peer.clientName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if peer.rateToClient > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down").font(.caption2)
                        Text(ByteFormatter.transferRate(peer.rateToClient)).font(.caption2)
                    }
                    .foregroundStyle(.blue)
                }
                if peer.rateToPeer > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up").font(.caption2)
                        Text(ByteFormatter.transferRate(peer.rateToPeer)).font(.caption2)
                    }
                    .foregroundStyle(.green)
                }
            }
            .monospacedDigit()

            Text(String(format: "%.0f%%", peer.progress * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
    }
}

// MARK: - Trackers Tab

struct DetailTrackersView: View {
    let torrent: Torrent

    var body: some View {
        if let trackers = torrent.trackerStats, !trackers.isEmpty {
            LazyVStack(spacing: 0) {
                ForEach(trackers) { tracker in
                    TrackerRowView(tracker: tracker)
                    Divider()
                }
            }
        } else {
            Text("No trackers available")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

struct TrackerRowView: View {
    let tracker: TrackerStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tracker.host)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Image(systemName: tracker.lastAnnounceSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(tracker.lastAnnounceSucceeded ? .green : .red)
                    .font(.caption)
            }

            if !tracker.lastAnnounceResult.isEmpty {
                Text(tracker.lastAnnounceResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if tracker.seederCount >= 0 {
                    Label("\(tracker.seederCount) seeds", systemImage: "arrow.up.circle")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if tracker.leecherCount >= 0 {
                    Label("\(tracker.leecherCount) leechers", systemImage: "arrow.down.circle")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                Spacer()
                if tracker.nextAnnounceTime > 0 {
                    let next = Date(timeIntervalSince1970: TimeInterval(tracker.nextAnnounceTime))
                    (Text("Next: ") + Text(next, style: .relative))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
