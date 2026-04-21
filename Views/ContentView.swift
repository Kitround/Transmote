import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(TorrentStore.self) private var store
    @State private var appToolbar = AppToolbar()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("showDetail") private var showDetail: Bool = false
    @AppStorage("compactMode") private var compactMode: Bool = false
    @State private var showAddMagnet = false
    @State private var showAddSheet = false
    @State private var dragOver = false

    var body: some View {
        @Bindable var store = store

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 240)
        } detail: {
            TorrentListView()
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .inspector(isPresented: $showDetail) {
                    TorrentDetailView()
                        .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
                }
        }
        .background(ToolbarInstaller(toolbar: appToolbar.toolbar))
        .onAppear {
            Task { await store.connectToActiveServer() }
            setupToolbar()
        }
        .onChange(of: store.connectionState.isConnected) { _, _ in syncToolbar() }
        .onChange(of: store.isAltSpeedEnabled)           { _, _ in syncToolbar() }
        .onChange(of: showDetail)                        { _, _ in syncToolbar() }
        .onChange(of: compactMode)                       { _, _ in syncToolbar() }
        .onChange(of: store.searchText)                  { _, text in appToolbar.updateSearchText(text) }
        .onDrop(of: [.fileURL, .url], isTargeted: $dragOver) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if dragOver {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 40))
                            Text("Drop to add")
                                .font(.headline)
                        }
                        .foregroundStyle(.secondary)
                    }
            }
        }
        .sheet(isPresented: $showAddMagnet) {
            AddMagnetView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddTorrentSheetView()
        }
    }

    // MARK: - Toolbar Setup

    private func setupToolbar() {
        appToolbar.onStartAll      = { Task { await store.startAll() } }
        appToolbar.onPauseAll      = { Task { await store.stopAll() } }
        appToolbar.onAddFile       = { openFilePicker() }
        appToolbar.onAddMagnet     = { showAddMagnet = true }
        appToolbar.onToggleTurtle  = { Task { await store.toggleAltSpeed() } }
        appToolbar.onToggleDetail  = { withAnimation { showDetail.toggle() } }
        appToolbar.onToggleCompact = { compactMode.toggle() }
        appToolbar.onSearch        = { store.searchText = $0 }
        syncToolbar()
    }

    private func syncToolbar() {
        appToolbar.update(
            connected:   store.connectionState.isConnected,
            altSpeed:    store.isAltSpeedEnabled,
            showDetail:  showDetail,
            compactMode: compactMode
        )
    }

    // MARK: - Drop / File

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "torrent")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task { try? await store.addFile(at: url) }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { try? await store.addFile(at: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.scheme == "magnet" else { return }
                    Task { try? await store.addMagnet(url.absoluteString) }
                }
            }
        }
        return true
    }
}
