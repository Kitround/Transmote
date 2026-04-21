# Transmote

A native macOS client for [Transmission](https://transmissionbt.com).

## Download

Grab the latest `.dmg` from the [Releases](https://github.com/Kitround/Transmote/releases) page.

**Requires macOS 14 Sonoma or later.**

## Features

- Manage multiple Transmission servers
- Start, pause, remove and add torrents (file or magnet link)
- Drag & drop support
- Detail panel with files, peers and trackers
- Menu bar with live speeds
- Turtle mode, bandwidth & queue settings
- Download completion notifications
- Customizable toolbar
- French localization

## Transmission Setup

Enable RPC in Transmission's preferences:

```json
{
  "rpc-enabled": true,
  "rpc-port": 9091
}
```

## License

MIT
