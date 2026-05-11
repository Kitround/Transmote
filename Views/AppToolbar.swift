import AppKit
import SwiftUI

// MARK: - Item Identifiers

extension NSToolbarItem.Identifier {
    static let startAll    = NSToolbarItem.Identifier("com.transmote.start-all")
    static let pauseAll    = NSToolbarItem.Identifier("com.transmote.pause-all")
    static let addFile     = NSToolbarItem.Identifier("com.transmote.add-file")
    static let addMagnet   = NSToolbarItem.Identifier("com.transmote.add-magnet")
    static let turtle      = NSToolbarItem.Identifier("com.transmote.turtle")
    static let detail      = NSToolbarItem.Identifier("com.transmote.detail")
    static let compactMode = NSToolbarItem.Identifier("com.transmote.compact-mode")
    static let search      = NSToolbarItem.Identifier("com.transmote.search")
}

// MARK: - AppToolbar

final class AppToolbar: NSObject, NSToolbarDelegate {

    let toolbar: NSToolbar

    // Actions wired by ContentView
    var onStartAll:      (() -> Void)?
    var onPauseAll:      (() -> Void)?
    var onAddFile:       (() -> Void)?
    var onAddMagnet:     (() -> Void)?
    var onToggleTurtle:  (() -> Void)?
    var onToggleDetail:  (() -> Void)?
    var onToggleCompact: (() -> Void)?
    var onSearch:        ((String) -> Void)?

    private var isConnected = false
    private var isAltSpeed  = false
    private var showDetail  = false
    private var compactMode = false

    override init() {
        toolbar = NSToolbar(identifier: "com.transmote.main")
        super.init()
        toolbar.delegate                = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration  = true
        toolbar.displayMode             = .iconOnly
    }

    // MARK: - State sync

    func update(connected: Bool, altSpeed: Bool, showDetail: Bool, compactMode: Bool) {
        isConnected      = connected
        isAltSpeed       = altSpeed
        self.showDetail  = showDetail
        self.compactMode = compactMode
        toolbar.items.forEach { refresh($0) }
    }

    func updateSearchText(_ text: String) {
        for item in toolbar.items {
            if let searchItem = item as? NSSearchToolbarItem,
               searchItem.searchField.stringValue != text {
                searchItem.searchField.stringValue = text
            }
        }
    }

    private func refresh(_ item: NSToolbarItem) {
        switch item.itemIdentifier {

        case .startAll, .pauseAll:
            item.isEnabled = isConnected

        case .turtle:
            item.isEnabled = isConnected
            let symbol = isAltSpeed ? "tortoise.fill" : "tortoise"
            let label  = isAltSpeed
                ? NSLocalizedString("Turtle mode active", comment: "Toolbar button label when turtle mode is active")
                : NSLocalizedString("Turtle mode", comment: "Toolbar button label when turtle mode is inactive")
            item.label = label
            if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
                item.image = isAltSpeed
                    ? base.withSymbolConfiguration(.init(paletteColors: [.systemBlue]))
                    : base
            }

        case .detail:
            item.label = showDetail
                ? NSLocalizedString("Hide Detail", comment: "Toolbar button label: hide inspector panel")
                : NSLocalizedString("Show Detail", comment: "Toolbar button label: show inspector panel")

        case .compactMode:
            let symbol = compactMode ? "list.bullet.indent" : "list.dash"
            let label = compactMode
                ? NSLocalizedString("Detailed view", comment: "Toolbar toggle label: switch to detailed row view")
                : NSLocalizedString("Compact view", comment: "Toolbar toggle label: switch to compact row view")
            let tooltip = compactMode
                ? NSLocalizedString("Switch to detailed view", comment: "Toolbar toggle tooltip")
                : NSLocalizedString("Switch to compact view", comment: "Toolbar toggle tooltip")
            item.label   = label
            item.toolTip = tooltip
            item.image   = NSImage(systemSymbolName: symbol, accessibilityDescription: label)

        default:
            break
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.startAll, .pauseAll, .space, .addFile, .addMagnet, .flexibleSpace, .turtle, .space, .detail, .compactMode, .search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.startAll, .pauseAll, .addFile, .addMagnet, .turtle, .detail, .compactMode, .search,
         .flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem? {

        // Search field uses a dedicated subclass
        if id == .search {
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.label        = NSLocalizedString("Search", comment: "Toolbar search field label")
            item.paletteLabel = NSLocalizedString("Search", comment: "Toolbar search field label")
            item.toolTip      = NSLocalizedString("Search torrents", comment: "Toolbar search field tooltip")
            item.searchField.placeholderString = NSLocalizedString("Search\u{2026}", comment: "Torrent list search field placeholder")
            item.searchField.target = self
            item.searchField.action = #selector(searchChanged(_:))
            return item
        }

        let item = NSToolbarItem(itemIdentifier: id)
        item.target = self

        switch id {
        case .startAll:
            item.label        = NSLocalizedString("Start All", comment: "Toolbar button: resume all torrents")
            item.paletteLabel = NSLocalizedString("Start All", comment: "Toolbar button: resume all torrents")
            item.toolTip      = NSLocalizedString("Start all torrents", comment: "Toolbar button tooltip: start all")
            item.image        = NSImage(systemSymbolName: "play.fill", accessibilityDescription: item.label)
            item.action       = #selector(startAllAction)
            item.isEnabled    = isConnected

        case .pauseAll:
            item.label        = NSLocalizedString("Pause All", comment: "Toolbar button: pause all torrents")
            item.paletteLabel = NSLocalizedString("Pause All", comment: "Toolbar button: pause all torrents")
            item.toolTip      = NSLocalizedString("Pause all torrents", comment: "Toolbar button tooltip: pause all")
            item.image        = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: item.label)
            item.action       = #selector(pauseAllAction)
            item.isEnabled    = isConnected

        case .addFile:
            item.label        = NSLocalizedString("Add File", comment: "Toolbar button: add a .torrent file")
            item.paletteLabel = NSLocalizedString("Add File", comment: "Toolbar button: add a .torrent file")
            item.toolTip      = NSLocalizedString("Add a .torrent file", comment: "Toolbar button tooltip: add file")
            item.image        = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: item.label)
            item.action       = #selector(addFileAction)

        case .addMagnet:
            item.label        = NSLocalizedString("Add Magnet", comment: "Toolbar button: add a magnet link")
            item.paletteLabel = NSLocalizedString("Add Magnet", comment: "Toolbar button: add a magnet link")
            item.toolTip      = NSLocalizedString("Add a magnet link", comment: "Toolbar button tooltip: add magnet")
            item.image        = NSImage(systemSymbolName: "link.badge.plus", accessibilityDescription: item.label)
            item.action       = #selector(addMagnetAction)

        case .turtle:
            item.paletteLabel = NSLocalizedString("Turtle mode", comment: "Toolbar button label when turtle mode is inactive")
            item.toolTip      = NSLocalizedString("Toggle alternative speed limit", comment: "Toolbar button tooltip: turtle mode")
            item.action       = #selector(turtleAction)
            refresh(item)

        case .detail:
            item.paletteLabel = NSLocalizedString("Detail Panel", comment: "Toolbar button label: inspector panel")
            item.toolTip      = NSLocalizedString("Toggle detail panel", comment: "Toolbar button tooltip: detail panel")
            item.image        = NSImage(systemSymbolName: "sidebar.trailing", accessibilityDescription: item.paletteLabel)
            item.action       = #selector(detailAction)
            refresh(item)

        case .compactMode:
            item.paletteLabel = NSLocalizedString("Compact view", comment: "Toolbar toggle label: switch to compact row view")
            item.action       = #selector(compactModeAction)
            refresh(item)

        default:
            return nil
        }

        return item
    }

    // MARK: - Actions

    @objc private func startAllAction()           { onStartAll?() }
    @objc private func pauseAllAction()           { onPauseAll?() }
    @objc private func addFileAction()            { onAddFile?() }
    @objc private func addMagnetAction()          { onAddMagnet?() }
    @objc private func turtleAction()             { onToggleTurtle?() }
    @objc private func detailAction()             { onToggleDetail?() }
    @objc private func compactModeAction()        { onToggleCompact?() }
    @objc private func searchChanged(_ sender: NSSearchField) { onSearch?(sender.stringValue) }
}

// MARK: - ToolbarInstaller (NSViewRepresentable)

struct ToolbarInstaller: NSViewRepresentable {
    let toolbar: NSToolbar

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.toolbar = toolbar
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard view.window?.toolbar !== toolbar else { return }
            view.window?.toolbar = toolbar
        }
    }
}
