import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(TorrentStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showDetail: Bool = false
    @AppStorage("compactMode") private var compactMode: Bool = false
    @State private var showAddMagnet = false
    @State private var dragOver = false

    var body: some View {
        @Bindable var store = store

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                // The system sidebar toggle has the same laggy hover; ours lives with the other buttons.
                .toolbar(removing: .sidebarToggle)
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
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(!store.connectionState.isConnected)
            }
            ToolbarItem(id: "pauseAll", placement: .primaryAction) {
                Button {
                    Task { await store.stopAll() }
                } label: {
                    Label("Pause All", systemImage: "pause.fill")
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(!store.connectionState.isConnected)
            }
            ToolbarItem(id: "addFile", placement: .primaryAction) {
                Button {
                    openFilePicker()
                } label: {
                    Label("Add File", systemImage: "plus.circle")
                }
                .buttonStyle(ToolbarHoverButtonStyle())
            }
            ToolbarItem(id: "addMagnet", placement: .primaryAction) {
                Button {
                    showAddMagnet = true
                } label: {
                    Label("Add Magnet", systemImage: "link.badge.plus")
                }
                .buttonStyle(ToolbarHoverButtonStyle())
            }
            ToolbarItem(id: "turtle", placement: .primaryAction) {
                Button {
                    Task { await store.toggleAltSpeed() }
                } label: {
                    // Only tint when active; the button style supplies the gray otherwise.
                    if store.isAltSpeedEnabled {
                        Label("Turtle mode active", systemImage: "tortoise.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Label("Turtle mode", systemImage: "tortoise")
                    }
                }
                .buttonStyle(ToolbarHoverButtonStyle())
                .disabled(!store.connectionState.isConnected)
            }
            ToolbarItem(id: "compactMode", placement: .primaryAction) {
                Button {
                    compactMode.toggle()
                } label: {
                    Label(compactMode ? "Detailed view" : "Compact view",
                          systemImage: compactMode ? "list.bullet.indent" : "list.dash")
                }
                .buttonStyle(ToolbarHoverButtonStyle())
            }
            ToolbarItem(id: "sidebar", placement: .primaryAction) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
                .buttonStyle(ToolbarHoverButtonStyle())
            }
            ToolbarItem(id: "detail", placement: .primaryAction) {
                Button {
                    withAnimation { showDetail.toggle() }
                } label: {
                    Label(showDetail ? "Hide Detail" : "Show Detail",
                          systemImage: "sidebar.trailing")
                }
                .buttonStyle(ToolbarHoverButtonStyle())
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
    }

    // MARK: - Drop / File

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("org.bittorrent.torrent") ?? .data]
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
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { try? await store.addFile(at: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.scheme == "magnet" else { return }
                    Task { try? await store.addMagnet(url.absoluteString) }
                }
            }
        }
        return handled
    }
}

// MARK: - Toolbar button style

/// The system toolbar bezel fades in late on hover; draw our own, instantly.
struct ToolbarHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .imageScale(.large)  // match native toolbar symbol size
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(minWidth: 28, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(configuration.isPressed ? 0.15 : (hovering && isEnabled ? 0.08 : 0)))
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
        }
    }
}
