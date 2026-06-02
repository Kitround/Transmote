import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(TorrentStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showDetail: Bool = false
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
            TorrentListView(onOpenDetail: {
                DispatchQueue.main.async { withAnimation { showDetail = true } }
            })
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .inspector(isPresented: $showDetail) {
                    TorrentDetailView()
                        .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
                }
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: Text("Search\u{2026}"))
        .toolbar(id: "transmote.main") {
            ToolbarItem(id: "startAll", placement: .primaryAction) {
                Button {
                    Task { await store.startAll() }
                } label: {
                    Label("Start All", systemImage: "play.fill")
                }
                .help("Start all torrents")
                .disabled(!store.connectionState.isConnected)
            }
            ToolbarItem(id: "pauseAll", placement: .primaryAction) {
                Button {
                    Task { await store.stopAll() }
                } label: {
                    Label("Pause All", systemImage: "pause.fill")
                }
                .help("Pause all torrents")
                .disabled(!store.connectionState.isConnected)
            }
            ToolbarItem(id: "addFile", placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Label("Add File", systemImage: "plus.circle")
                }
                .help("Add a .torrent file")
            }
            ToolbarItem(id: "addMagnet", placement: .primaryAction) {
                Button {
                    showAddMagnet = true
                } label: {
                    Label("Add Magnet", systemImage: "link.badge.plus")
                }
                .help("Add a magnet link")
            }
            ToolbarItem(id: "turtle", placement: .primaryAction) {
                Button {
                    Task { await store.toggleAltSpeed() }
                } label: {
                    Label(store.isAltSpeedEnabled ? "Turtle mode active" : "Turtle mode",
                          systemImage: store.isAltSpeedEnabled ? "tortoise.fill" : "tortoise")
                }
                .help("Toggle alternative speed limit")
                .disabled(!store.connectionState.isConnected)
                .foregroundStyle(store.isAltSpeedEnabled ? Color.accentColor : Color.primary)
            }
            ToolbarItem(id: "compactMode", placement: .primaryAction) {
                Button {
                    compactMode.toggle()
                } label: {
                    Label(compactMode ? "Detailed view" : "Compact view",
                          systemImage: compactMode ? "list.bullet.indent" : "list.dash")
                }
                .help(compactMode ? "Switch to detailed view" : "Switch to compact view")
            }
            ToolbarItem(id: "detail", placement: .primaryAction) {
                Button {
                    withAnimation { showDetail.toggle() }
                } label: {
                    Label(showDetail ? "Hide Detail" : "Show Detail",
                          systemImage: "sidebar.trailing")
                }
                .help("Toggle detail panel")
            }
        }
        .onAppear {
            Task { await store.connectToActiveServer() }
        }
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
