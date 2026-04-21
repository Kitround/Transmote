import SwiftUI

struct TorrentCommands: Commands {
    let store: TorrentStore

    var body: some Commands {
        CommandMenu("Torrent") {
            Button("Start Selection") {
                Task { await store.start(ids: Array(store.selectedTorrentIDs)) }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store.selectedTorrentIDs.isEmpty)

            Button("Pause Selection") {
                Task { await store.stop(ids: Array(store.selectedTorrentIDs)) }
            }
            .keyboardShortcut("p", modifiers: [.command])
            .disabled(store.selectedTorrentIDs.isEmpty)

            Divider()

            Button("Verify Local Data") {
                Task { await store.verify(ids: Array(store.selectedTorrentIDs)) }
            }
            .disabled(store.selectedTorrentIDs.isEmpty)

            Button("Reannounce to Trackers") {
                Task { await store.reannounce(ids: Array(store.selectedTorrentIDs)) }
            }
            .disabled(store.selectedTorrentIDs.isEmpty)

            Divider()

            Button("Refresh") {
                Task { await store.fetchTorrents() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
