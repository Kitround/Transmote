# Transmote

A native macOS client for [Transmission](https://transmissionbt.com) via its JSON-RPC API.

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+
- Transmission running on a local or remote server with RPC enabled

---

## Installation

Clone the repository and open the project in Xcode:

```bash
git clone https://github.com/Kitround/Transmote.git
cd Transmote
open Transmote.xcodeproj
```

Build and run with **⌘R**.

---

## Transmission Setup

In Transmission's preferences (or `settings.json`):

```json
{
  "rpc-enabled": true,
  "rpc-port": 9091,
  "rpc-whitelist-enabled": false,
  "rpc-authentication-required": false
}
```

To enable authentication:
```json
{
  "rpc-authentication-required": true,
  "rpc-username": "admin",
  "rpc-password": "yourpassword"
}
```

---

## Features

| Feature | Status |
|---|---|
| Torrent list with sorting and filtering | ✅ |
| Start / Pause / Remove torrents | ✅ |
| Add .torrent file (drag & drop, file picker) | ✅ |
| Add magnet link | ✅ |
| Detail panel: info, files, peers, trackers | ✅ |
| Per-file priority control | ✅ |
| Multiple server management | ✅ |
| Menu bar with live speeds | ✅ |
| Download completion notifications | ✅ |
| Turtle mode (alternative speed limits) | ✅ |
| Bandwidth, peers & queue preferences | ✅ |
| Customizable and persistent toolbar | ✅ |
| French localization | ✅ |

---

## Project Structure

```
Transmote/
├── App/
│   ├── TransmoteApp.swift          # @main, SwiftUI scenes
│   └── AppDelegate.swift           # Menu bar, notifications
│
├── Networking/
│   ├── RPCClient.swift             # JSON-RPC client (actor)
│   └── RPCMethods.swift            # All Transmission RPC methods
│
├── Models/
│   ├── Torrent.swift               # Torrent model + enums
│   └── Server.swift                # ServerConfig, SessionArguments, Stats
│
├── Store/
│   └── TorrentStore.swift          # @Observable — central app state
│
├── Views/
│   ├── ContentView.swift           # NavigationSplitView + toolbar
│   ├── AppToolbar.swift            # NSToolbar with full customization
│   ├── Sidebar/
│   │   └── SidebarView.swift       # Filters + server management
│   ├── TorrentList/
│   │   └── TorrentListView.swift   # Table + context menu
│   ├── TorrentDetail/
│   │   └── TorrentDetailView.swift # Info, files, peers, trackers
│   ├── Sheets/
│   │   ├── AddTorrentViews.swift   # Add magnet / file
│   │   └── ServerEditView.swift    # Server editor
│   └── Settings/
│       └── SettingsView.swift      # Transmission preferences
│
└── Helpers/
    └── Formatters.swift            # ByteFormatter, ETAFormatter, etc.
```

---

## Transmission RPC Methods Used

| Method | Purpose |
|---|---|
| `torrent-get` | Fetch torrent list and details |
| `torrent-start` / `torrent-stop` | Resume / pause |
| `torrent-remove` | Remove torrent |
| `torrent-add` | Add magnet link or .torrent file |
| `torrent-set` | File priority, speed limits |
| `torrent-verify` | Verify local data |
| `torrent-reannounce` | Reannounce to trackers |
| `session-get` / `session-set` | Server preferences |
| `session-stats` | Global statistics |
| `free-space` | Available disk space |

---

## Dependencies

**None.** The project uses only Apple frameworks:
- SwiftUI + AppKit
- URLSession
- UserNotifications
- UniformTypeIdentifiers

---

## Contributing

Contributions are welcome! Ideas for improvement:
- Additional localizations
- macOS widget for live speeds
- Spotlight integration
- Tracker announce URL sequence support

---

## License

MIT — see LICENSE
