import SwiftUI

@main
struct TransmoteApp: App {
    @State private var store = TorrentStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Transmote", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 500)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                    appDelegate.store = store
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        .commands {
            TorrentCommands(store: store)
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
