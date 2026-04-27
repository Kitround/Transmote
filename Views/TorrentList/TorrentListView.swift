import SwiftUI

struct TorrentListView: View {
    @Environment(TorrentStore.self) private var store
    var onOpenDetail: (() -> Void)? = nil
    @State private var sortOrder = [KeyPathComparator(\Torrent.addedDate, order: .reverse)]
    @AppStorage("compactMode") private var compactMode = false
    @State private var columnCustomization = TorrentListView.loadColumnCustomization()

    var body: some View {
        @Bindable var store = store

        Group {
            if store.torrents.isEmpty && store.connectionState.isConnected {
                emptyState
            } else if case .disconnected = store.connectionState {
                disconnectedState
            } else if case .error(let msg) = store.connectionState {
                errorState(msg)
            } else {
                torrentTable
            }
        }
    }

    // MARK: - Table

    private var torrentTable: some View {
        Table(
            store.filteredTorrents,
            selection: Binding(
                get: { store.selectedTorrentIDs },
                set: { store.selectedTorrentIDs = $0 }
            ),
            sortOrder: $sortOrder,
            columnCustomization: $columnCustomization
        ) {
            TableColumn("Name", value: \.name) { torrent in
                if compactMode {
                    CompactNameCell(torrent: torrent)
                } else {
                    TorrentNameCell(torrent: torrent)
                }
            }
            .width(min: 200)
            .customizationID("name")

            TableColumn("Size", value: \.totalSize) { torrent in
                Text(ByteFormatter.size(torrent.totalSize))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(70)
            .customizationID("size")

            TableColumn("Progress", value: \.percentDone) { torrent in
                ProgressCell(torrent: torrent)
            }
            .width(80)
            .customizationID("progress")

            TableColumn("Download", value: \.rateDownload) { torrent in
                if torrent.rateDownload > 0 {
                    Text(ByteFormatter.transferRate(torrent.rateDownload))
                        .font(.callout)
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                } else {
                    Text("—").font(.callout).foregroundStyle(.tertiary)
                }
            }
            .width(90)
            .customizationID("downloadSpeed")

            TableColumn("Upload", value: \.rateUpload) { torrent in
                if torrent.rateUpload > 0 {
                    Text(ByteFormatter.transferRate(torrent.rateUpload))
                        .font(.callout)
                        .foregroundStyle(.green)
                        .monospacedDigit()
                } else {
                    Text("—").font(.callout).foregroundStyle(.tertiary)
                }
            }
            .width(90)
            .customizationID("uploadSpeed")

            TableColumn("Ratio", value: \.uploadRatio) { torrent in
                Text(RatioFormatter.format(torrent.uploadRatio))
                    .font(.callout)
                    .foregroundStyle(ratioColor(for: torrent))
                    .monospacedDigit()
            }
            .width(55)
            .customizationID("ratio")

            TableColumn("ETA", value: \.eta) { torrent in
                Text(torrent.etaDuration)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(65)
            .customizationID("eta")

            TableColumn("Added", value: \.addedDate) { torrent in
                Text(Date(timeIntervalSince1970: Double(torrent.addedDate)), style: .date)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 100)
            .customizationID("addedDate")
        }
        .onChange(of: sortOrder) { _, new in
            applySortOrder(new)
        }
        .onChange(of: columnCustomization) { _, new in
            TorrentListView.saveColumnCustomization(new)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            torrentContextMenu(for: Array(ids))
        } primaryAction: { ids in
            guard !ids.isEmpty else { return }
            onOpenDetail?()
        }
    }

    // MARK: - Context Menu (shared)

    @ViewBuilder
    private func folderSubmenu(for ids: [Int]) -> some View {
        let dirs = store.downloadDirs
        if !dirs.isEmpty {
            Menu("Move to…") {
                ForEach(dirs, id: \.self) { path in
                    Button {
                        Task { await store.moveTorrents(ids, toDirectory: path) }
                    } label: {
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "folder")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func torrentContextMenu(for ids: [Int]) -> some View {
        let torrents = store.torrents.filter { ids.contains($0.id) }
        let allStopped = torrents.allSatisfy { $0.status.isStopped }
        let allActive = torrents.allSatisfy { $0.status.isActive }

        if allStopped {
            Button("Start") { Task { await store.start(ids: ids) } }
        }
        if allActive {
            Button("Pause") { Task { await store.stop(ids: ids) } }
        }
        if !allStopped && !allActive {
            Button("Start") { Task { await store.start(ids: ids) } }
            Button("Pause") { Task { await store.stop(ids: ids) } }
        }

        Divider()

        folderSubmenu(for: ids)

        Divider()

        Button("Verify Local Data") {
            Task { await store.verify(ids: ids) }
        }
        Button("Reannounce to Trackers") {
            Task { await store.reannounce(ids: ids) }
        }

        if let torrent = torrents.first, ids.count == 1 {
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: torrent.downloadDir)
            }
            Button("Copy Hash") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(torrent.hashString, forType: .string)
            }
        }

        Divider()

        Button("Remove", role: .destructive) {
            Task { await store.remove(ids: ids, deleteData: false) }
        }
        Button("Remove and Delete Data", role: .destructive) {
            Task { await store.remove(ids: ids, deleteData: true) }
        }
    }

    // MARK: - Empty / Error States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Torrents", systemImage: "tray")
        } description: {
            Text("Add a .torrent file or magnet link\nto start downloading.")
        }
    }

    private var disconnectedState: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "wifi.slash")
        } description: {
            Text("Select a server in the sidebar\nor check your connection.")
        } actions: {
            Button("Connect") {
                Task { await store.connectToActiveServer() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Connection Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await store.connectToActiveServer() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Column Customization Persistence

    private static let columnCustomizationKey = "columnCustomization"

    private static func loadColumnCustomization() -> TableColumnCustomization<Torrent> {
        guard let data = UserDefaults.standard.data(forKey: columnCustomizationKey),
              let value = try? JSONDecoder().decode(TableColumnCustomization<Torrent>.self, from: data)
        else { return TableColumnCustomization<Torrent>() }
        return value
    }

    private static func saveColumnCustomization(_ value: TableColumnCustomization<Torrent>) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: columnCustomizationKey)
        }
    }

    // MARK: - Sort Helpers

    private func applySortOrder(_ order: [KeyPathComparator<Torrent>]) {
        guard let first = order.first else { return }
        let ascending = first.order == .forward

        switch first.keyPath {
        case \Torrent.name:
            store.sortOrder = .name
        case \Torrent.totalSize:
            store.sortOrder = .size
        case \Torrent.percentDone:
            store.sortOrder = .progress
        case \Torrent.rateDownload:
            store.sortOrder = .downloadSpeed
        case \Torrent.rateUpload:
            store.sortOrder = .uploadSpeed
        case \Torrent.uploadRatio:
            store.sortOrder = .ratio
        case \Torrent.eta:
            store.sortOrder = .eta
        case \Torrent.addedDate:
            store.sortOrder = .addedDate
        default:
            break
        }
        store.sortAscending = ascending
    }

    private func ratioColor(for torrent: Torrent) -> Color {
        guard store.session?.seedRatioLimited == true,
              let limit = store.session?.seedRatioLimit,
              torrent.uploadRatio >= limit else { return .secondary }
        return .green
    }
}

// MARK: - Compact Name Cell

struct CompactNameCell: View {
    let torrent: Torrent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(torrent.statusColor)
                .frame(width: 6, height: 6)

            Text(torrent.name)
                .font(.callout)
                .lineLimit(1)

            if torrent.hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
            }
            if torrent.isPrivate {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Torrent Name Cell

struct TorrentNameCell: View {
    let torrent: Torrent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Status indicator dot
                Circle()
                    .fill(torrent.statusColor)
                    .frame(width: 7, height: 7)
                    .overlay {
                        if torrent.status == .check || torrent.status == .checkWait {
                            Circle().stroke(torrent.statusColor, lineWidth: 1.5)
                                .scaleEffect(1.5)
                                .opacity(0.4)
                        }
                    }

                Text(torrent.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if torrent.hasError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if torrent.isPrivate {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressBarColor)
                        .frame(width: geo.size.width * torrent.progress, height: 3)
                }
            }
            .frame(height: 3)

            HStack(spacing: 6) {
                StatusBadge(torrent: torrent)
                Text("·")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text(ByteFormatter.size(torrent.downloadedSize))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("/")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text(ByteFormatter.size(torrent.sizeWhenDone))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if torrent.hasError {
                    Text("·").foregroundStyle(.tertiary).font(.caption2)
                    Text(torrent.errorString)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var progressBarColor: Color {
        if torrent.hasError { return .red }
        switch torrent.status {
        case .download, .downloadWait: return .blue
        case .seed, .seedWait: return .secondary
        case .stopped: return .gray
        case .check, .checkWait: return .orange
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let torrent: Torrent

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .semibold))
            Text(torrent.status.description)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(torrent.status.isStopped && !torrent.hasError ? AnyShapeStyle(.secondary) : AnyShapeStyle(torrent.statusColor))
    }

    private var iconName: String {
        switch torrent.status {
        case .download, .downloadWait: return "arrow.down"
        case .seed, .seedWait:         return "arrow.up"
        case .stopped:                 return "pause.fill"
        case .check, .checkWait:       return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Progress Cell

struct ProgressCell: View {
    let torrent: Torrent

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(ProgressFormatter.format(torrent.progress))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(torrent.progress >= 1 ? .secondary : .primary)
            if torrent.status == .check {
                Text("check. \(ProgressFormatter.format(torrent.recheckProgress))")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - Folder Section Header

struct FolderSectionHeader: View {
    let path: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Spacer()
            Text(verbatim: "\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
        .help(path)
    }
}
