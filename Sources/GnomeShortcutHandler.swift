// This file getting too long is unavoidable due to the large number of shortcuts
// swiftlint:disable file_length
import Cocoa

struct GnomeShortcutDef: Identifiable, Hashable {
    let id: String
    let label: String
    let fromKeys: String
    let toKeys: String
    let category: String
}

// GnomeShortcutHandler is strictly for 1:1 keyboard shortcut remappings — one input
// key combo maps to one output key combo. Features that involve state (FinderCutHandler),
// different event types (ScrollZoomHandler), AX manipulation (ZoomButtonHandler), or
// non-keyboard input (MiddleClickPasteHandler) belong in their own handler class with a
// switch toggle in Settings.
@MainActor
class GnomeShortcutHandler {
    // MARK: - Terminal detection

    private static let terminalPassthroughKeys: Set<Int64> = [
        0x08, // C - interrupt
        0x02, // D - EOF
        0x0E, // E - end of line
        0x25, // L - clear
        0x20, // U - delete to start of line
        0x0D, // W - delete previous word
        0x06, // Z - suspend
        0x33, // Delete - delete previous word
        0x75, // Forward Delete - delete next word
        0x7B, // Left arrow - move cursor left (including by character)
        0x7C // Right arrow - move cursor right (including by character)
    ]

    // Ctrl+Shift+key in terminal apps → Cmd+key (removes both Ctrl and Shift)
    private static let terminalShiftMap: [Int64: String] = [
        0x08: "termCopy",        // C
        0x09: "termPaste",       // V
        0x11: "termNewTab",      // T
        0x0D: "termCloseTab",    // W
        0x0C: "termCloseWindow" // Q
    ]

    // MARK: - Key code maps

    // Ctrl+Shift+key shortcuts with their own toggle (checked before base Ctrl+key)
    private static let ctrlShiftMap: [Int64: [String]] = [
        0x11: ["reopenTab"],                    // T
        0x23: ["commandPalette", "privateWindow"], // P
        0x28: ["deleteLine"],                   // K
        0x24: ["insertLineAbove"],              // Return
        0x2D: ["newWindow"],                    // N
        0x05: ["findPrev"],                     // G
        0x0B: ["bookmarksBar"],                 // B
        0x75: ["clearData"]                     // Forward Delete
    ]

    // Ctrl+key → Cmd+key (simple modifier swap)
    private static let ctrlToCmdMap: [Int64: [String]] = [
        0x00: ["selectAll"],       // A
        0x0B: ["bold"],            // B
        0x08: ["copy"],            // C
        0x02: ["duplicate", "bookmark"], // D
        0x0E: ["searchSelection"], // E
        0x03: ["find"],            // F
        0x05: ["findNext"],        // G
        0x22: ["italic"],          // I
        0x26: ["downloads"],       // J
        0x28: ["hyperlink"],       // K
        0x25: ["addressBar"],      // L
        0x2D: ["new"],             // N
        0x23: ["print"],           // P
        0x0C: ["quit"],            // Q
        0x0F: ["reload"],          // R
        0x01: ["save"],            // S
        0x11: ["newTab"],          // T
        0x20: ["underline", "viewSource"], // U
        0x09: ["paste"],           // V
        0x0D: ["closeTab"],        // W
        0x07: ["cut"],             // X
        0x06: ["undo"],            // Z
        0x18: ["zoomIn"],          // = (+)
        0x1B: ["zoomOut"],         // -
        0x1D: ["zoomReset"],       // 0
        0x2B: ["settings"],        // ,
        0x2C: ["toggleComment"],   // /
        0x1E: ["indent"],          // ]
        0x21: ["outdent"],         // [
        0x24: ["cmdEnter"]        // Return
    ]

    // MARK: - Key codes

    private static let keyY: Int64 = 0x10
    private static let keyZ: Int64 = 0x06
    private static let keyDelete: Int64 = 0x33
    private static let keyLeft: Int64 = 0x7B
    private static let keyRight: Int64 = 0x7C
    private static let keyUp: Int64 = 0x7E
    private static let keyDown: Int64 = 0x7D
    private static let keyF4: Int64 = 0x76
    private static let keyReturn: Int64 = 0x24
    private static let keyI: Int64 = 0x22
    private static let keyW: Int64 = 0x0D
    private static let keyL: Int64 = 0x25
    private static let keyQ: Int64 = 0x0C
    private static let keyH: Int64 = 0x04
    private static let keyF: Int64 = 0x03
    private static let keyForwardDelete: Int64 = 0x75
    private static let keyF2: Int64 = 0x78
    private static let keyF11: Int64 = 0x67
    private static let keyF12: Int64 = 0x6F
    private static let keyTab: Int64 = 0x30

    // MARK: - Runtime state

    private var disabledShortcuts: Set<String> = []

    init() { reloadSettings() }

    func reloadSettings() {
        disabledShortcuts = Set(
            UserDefaults.standard.stringArray(forKey: "gnomeDisabledShortcuts") ?? [])
    }

    private static let finderOnlyShortcuts: Set<String> = Set(
        allShortcuts.filter { $0.category == finder }.map(\.id))
    private static let terminalOnlyShortcuts: Set<String> = Set(
        allShortcuts.filter { $0.category == terminal }.map(\.id))
    private static let browserOnlyShortcuts: Set<String> = Set(
        allShortcuts.filter { $0.category == browsers }.map(\.id))
    private static let codeEditorOnlyShortcuts: Set<String> = Set(
        allShortcuts.filter { $0.category == codeEditor }.map(\.id))

    private func isEnabled(_ id: String) -> Bool {
        if disabledShortcuts.contains(id) { return false }
        if Self.finderOnlyShortcuts.contains(id) && !KeyboardUtils.isFinderApp() { return false }
        if Self.terminalOnlyShortcuts.contains(id) && !KeyboardUtils.isTerminalApp() { return false }
        if Self.browserOnlyShortcuts.contains(id) && !KeyboardUtils.isBrowserApp() { return false }
        if Self.codeEditorOnlyShortcuts.contains(id) && !KeyboardUtils.isCodeEditorApp() { return false }
        return true
    }

    private func remap(_ event: CGEvent, _ keyCode: Int64, flags: CGEventFlags,
                       remove: CGEventFlags = [], add: CGEventFlags = []) -> Bool {
        var newFlags = flags; newFlags.remove(remove); newFlags.insert(add)
        KeyboardUtils.rewriteEvent(event, keyCode: keyCode, flags: newFlags)
        return true
    }

}

// MARK: - Shortcut data

extension GnomeShortcutHandler {
    // genstrings requires literal NSLocalizedString calls — can't use a wrapper function
    static let general = NSLocalizedString("General", comment: "Shortcut category")
    static let file = NSLocalizedString("File", comment: "Shortcut category")
    static let view = NSLocalizedString("View", comment: "Shortcut category")
    static let textEditing = NSLocalizedString("Text Editing", comment: "Shortcut category")
    static let finder = NSLocalizedString("Finder", comment: "Shortcut category")
    static let tabsWindows = NSLocalizedString("Tabs & Windows", comment: "Shortcut category")
    static let browsers = NSLocalizedString("Browsers", comment: "Shortcut category")
    static let terminal = NSLocalizedString("Terminal", comment: "Shortcut category")
    static let codeEditor = NSLocalizedString("Code Editor", comment: "Shortcut category")

    static let categories = [general, file, view, textEditing, finder, tabsWindows, browsers, terminal, codeEditor]

    // Tabular data — each shortcut definition is one line for readability.
    // swiftlint:disable line_length
    static let allShortcuts: [GnomeShortcutDef] = [
        GnomeShortcutDef(id: "copy", label: NSLocalizedString("Copy", comment: ""), fromKeys: "⌃C", toKeys: "⌘C", category: general),
        GnomeShortcutDef(id: "cut", label: NSLocalizedString("Cut", comment: ""), fromKeys: "⌃X", toKeys: "⌘X", category: general),
        GnomeShortcutDef(id: "paste", label: NSLocalizedString("Paste", comment: ""), fromKeys: "⌃V", toKeys: "⌘V", category: general),
        GnomeShortcutDef(id: "undo", label: NSLocalizedString("Undo", comment: ""), fromKeys: "⌃Z", toKeys: "⌘Z", category: general),
        GnomeShortcutDef(id: "redo", label: NSLocalizedString("Redo", comment: ""), fromKeys: "⌃Y", toKeys: "⇧⌘Z", category: general),
        GnomeShortcutDef(id: "selectAll", label: NSLocalizedString("Select All", comment: ""), fromKeys: "⌃A", toKeys: "⌘A", category: general),
        GnomeShortcutDef(id: "find", label: NSLocalizedString("Find", comment: ""), fromKeys: "⌃F", toKeys: "⌘F", category: general),
        GnomeShortcutDef(id: "findNext", label: NSLocalizedString("Find Next", comment: ""), fromKeys: "⌃G", toKeys: "⌘G", category: general),
        GnomeShortcutDef(id: "findPrev", label: NSLocalizedString("Find Previous", comment: ""), fromKeys: "⌃⇧G", toKeys: "⇧⌘G", category: general),
        GnomeShortcutDef(id: "newWindow", label: NSLocalizedString("New Window", comment: ""), fromKeys: "⌃⇧N", toKeys: "⇧⌘N", category: general),
        GnomeShortcutDef(id: "lockScreen", label: NSLocalizedString("Lock Screen", comment: ""), fromKeys: "⌥L", toKeys: "⌃⌘Q", category: general),
        GnomeShortcutDef(id: "cmdEnter", label: NSLocalizedString("Run/Confirm", comment: ""), fromKeys: "⌃↩", toKeys: "⌘↩", category: general),
        GnomeShortcutDef(id: "hyperlink", label: NSLocalizedString("Insert Link", comment: ""), fromKeys: "⌃K", toKeys: "⌘K", category: general),

        GnomeShortcutDef(id: "new", label: NSLocalizedString("New", comment: ""), fromKeys: "⌃N", toKeys: "⌘N", category: file),
        GnomeShortcutDef(id: "save", label: NSLocalizedString("Save", comment: ""), fromKeys: "⌃S", toKeys: "⌘S", category: file),
        GnomeShortcutDef(id: "print", label: NSLocalizedString("Print", comment: ""), fromKeys: "⌃P", toKeys: "⌘P", category: file),
        GnomeShortcutDef(id: "quit", label: NSLocalizedString("Quit", comment: ""), fromKeys: "⌃Q", toKeys: "⌘Q", category: file),

        GnomeShortcutDef(id: "zoomIn", label: NSLocalizedString("Zoom In", comment: ""), fromKeys: "⌃+", toKeys: "⌘+", category: view),
        GnomeShortcutDef(id: "zoomOut", label: NSLocalizedString("Zoom Out", comment: ""), fromKeys: "⌃-", toKeys: "⌘-", category: view),
        GnomeShortcutDef(id: "zoomReset", label: NSLocalizedString("Reset Zoom", comment: ""), fromKeys: "⌃0", toKeys: "⌘0", category: view),
        GnomeShortcutDef(id: "fullscreen", label: NSLocalizedString("Full Screen", comment: ""), fromKeys: "F11", toKeys: "⌃⌘F", category: view),

        GnomeShortcutDef(id: "getInfo", label: NSLocalizedString("Properties", comment: ""), fromKeys: "⌥↩", toKeys: "⌘I", category: finder),
        GnomeShortcutDef(id: "finderDelete", label: NSLocalizedString("Move to Trash", comment: ""), fromKeys: "⌦", toKeys: "⌘⌫", category: finder),
        GnomeShortcutDef(id: "rename", label: NSLocalizedString("Rename", comment: ""), fromKeys: "F2", toKeys: "↩", category: finder),

        GnomeShortcutDef(id: "bold", label: NSLocalizedString("Bold", comment: ""), fromKeys: "⌃B", toKeys: "⌘B", category: textEditing),
        GnomeShortcutDef(id: "italic", label: NSLocalizedString("Italic", comment: ""), fromKeys: "⌃I", toKeys: "⌘I", category: textEditing),
        GnomeShortcutDef(id: "underline", label: NSLocalizedString("Underline", comment: ""), fromKeys: "⌃U", toKeys: "⌘U", category: textEditing),
        GnomeShortcutDef(id: "deleteWord", label: NSLocalizedString("Delete Word", comment: ""), fromKeys: "⌃⌫", toKeys: "⌥⌫", category: textEditing),
        GnomeShortcutDef(id: "forwardDeleteWord", label: NSLocalizedString("Forward Delete Word", comment: ""), fromKeys: "⌃⌦", toKeys: "⌥⌦", category: textEditing),
        GnomeShortcutDef(id: "wordLeft", label: NSLocalizedString("Word Left", comment: ""), fromKeys: "⌃←", toKeys: "⌥←", category: textEditing),
        GnomeShortcutDef(id: "wordRight", label: NSLocalizedString("Word Right", comment: ""), fromKeys: "⌃→", toKeys: "⌥→", category: textEditing),
        GnomeShortcutDef(id: "selectWordLeft", label: NSLocalizedString("Select Word Left", comment: ""), fromKeys: "⌃⇧←", toKeys: "⌥⇧←", category: textEditing),
        GnomeShortcutDef(id: "selectWordRight", label: NSLocalizedString("Select Word Right", comment: ""), fromKeys: "⌃⇧→", toKeys: "⌥⇧→", category: textEditing),
        GnomeShortcutDef(id: "selectDown", label: NSLocalizedString("Select Down", comment: ""), fromKeys: "⌃⇧↓", toKeys: "⇧↓", category: textEditing),
        GnomeShortcutDef(id: "selectUp", label: NSLocalizedString("Select Up", comment: ""), fromKeys: "⌃⇧↑", toKeys: "⇧↑", category: textEditing),

        GnomeShortcutDef(id: "newTab", label: NSLocalizedString("New Tab", comment: ""), fromKeys: "⌃T", toKeys: "⌘T", category: tabsWindows),
        GnomeShortcutDef(id: "closeTab", label: NSLocalizedString("Close Tab", comment: ""), fromKeys: "⌃W", toKeys: "⌘W", category: tabsWindows),
        GnomeShortcutDef(id: "reopenTab", label: NSLocalizedString("Reopen Tab", comment: ""), fromKeys: "⌃⇧T", toKeys: "⇧⌘T", category: tabsWindows),
        GnomeShortcutDef(id: "closeWindow", label: NSLocalizedString("Close Window", comment: ""), fromKeys: "⌥F4", toKeys: "⌘W", category: tabsWindows),

        GnomeShortcutDef(id: "addressBar", label: NSLocalizedString("Address Bar", comment: ""), fromKeys: "⌃L", toKeys: "⌘L", category: browsers),
        GnomeShortcutDef(id: "downloads", label: NSLocalizedString("Downloads", comment: ""), fromKeys: "⌃J", toKeys: "⌘J", category: browsers),
        GnomeShortcutDef(id: "reload", label: NSLocalizedString("Reload", comment: ""), fromKeys: "⌃R", toKeys: "⌘R", category: browsers),
        GnomeShortcutDef(id: "devTools", label: NSLocalizedString("Developer Tools", comment: ""), fromKeys: "⌃⇧I", toKeys: "⌥⌘I", category: browsers),
        GnomeShortcutDef(id: "devToolsF12", label: NSLocalizedString("Developer Tools", comment: ""), fromKeys: "F12", toKeys: "⌥⌘I", category: browsers),
        GnomeShortcutDef(id: "viewHistory", label: NSLocalizedString("View History", comment: ""), fromKeys: "⌃H", toKeys: "⌘Y", category: browsers),
        GnomeShortcutDef(id: "viewSource", label: NSLocalizedString("View Source", comment: ""), fromKeys: "⌃U", toKeys: "⌘U", category: browsers),
        GnomeShortcutDef(id: "privateWindow", label: NSLocalizedString("New Private Window", comment: ""), fromKeys: "⌃⇧P", toKeys: "⇧⌘P", category: browsers),
        GnomeShortcutDef(id: "bookmark", label: NSLocalizedString("Bookmark Page", comment: ""), fromKeys: "⌃D", toKeys: "⌘D", category: browsers),
        GnomeShortcutDef(id: "bookmarksBar", label: NSLocalizedString("Show or Hide Bookmarks Bar", comment: ""), fromKeys: "⌃⇧B", toKeys: "⇧⌘B", category: browsers),
        GnomeShortcutDef(id: "clearData", label: NSLocalizedString("Clear Browsing Data", comment: ""), fromKeys: "⌃⇧⌦", toKeys: "⇧⌘⌫", category: browsers),

        GnomeShortcutDef(id: "termCopy", label: NSLocalizedString("Copy", comment: ""), fromKeys: "⌃⇧C", toKeys: "⌘C", category: terminal),
        GnomeShortcutDef(id: "termPaste", label: NSLocalizedString("Paste", comment: ""), fromKeys: "⌃⇧V", toKeys: "⌘V", category: terminal),
        GnomeShortcutDef(id: "termCloseTab", label: NSLocalizedString("Close Tab", comment: ""), fromKeys: "⌃⇧W", toKeys: "⌘W", category: terminal),
        GnomeShortcutDef(id: "termCloseWindow", label: NSLocalizedString("Close Window", comment: ""), fromKeys: "⌃⇧Q", toKeys: "⌘Q", category: terminal),
        GnomeShortcutDef(id: "termNewTab", label: NSLocalizedString("New Tab", comment: ""), fromKeys: "⌃⇧T", toKeys: "⌘T", category: terminal),

        GnomeShortcutDef(id: "settings", label: NSLocalizedString("Settings", comment: ""), fromKeys: "⌃,", toKeys: "⌘,", category: codeEditor),
        GnomeShortcutDef(id: "toggleComment", label: NSLocalizedString("Comment or Uncomment", comment: ""), fromKeys: "⌃/", toKeys: "⌘/", category: codeEditor),
        GnomeShortcutDef(id: "indent", label: NSLocalizedString("Indent", comment: ""), fromKeys: "⌃]", toKeys: "⌘]", category: codeEditor),
        GnomeShortcutDef(id: "outdent", label: NSLocalizedString("Outdent", comment: ""), fromKeys: "⌃[", toKeys: "⌘[", category: codeEditor),
        GnomeShortcutDef(id: "commandPalette", label: NSLocalizedString("Command Palette", comment: ""), fromKeys: "⌃⇧P", toKeys: "⇧⌘P", category: codeEditor),
        GnomeShortcutDef(id: "deleteLine", label: NSLocalizedString("Delete Line", comment: ""), fromKeys: "⌃⇧K", toKeys: "⇧⌘K", category: codeEditor),
        GnomeShortcutDef(id: "insertLineAbove", label: NSLocalizedString("Insert Line Above", comment: ""), fromKeys: "⌃⇧↩", toKeys: "⇧⌘↩", category: codeEditor),
        GnomeShortcutDef(id: "duplicate", label: NSLocalizedString("Duplicate", comment: ""), fromKeys: "⌃D", toKeys: "⌘D", category: codeEditor),
        GnomeShortcutDef(id: "searchSelection", label: NSLocalizedString("Search Selection", comment: ""), fromKeys: "⌃E", toKeys: "⌘E", category: codeEditor),
        GnomeShortcutDef(id: "findReplace", label: NSLocalizedString("Find and Replace", comment: ""), fromKeys: "⌃H", toKeys: "⌥⌘F", category: codeEditor),
        GnomeShortcutDef(id: "moveLineUp", label: NSLocalizedString("Move Line Up", comment: ""), fromKeys: "⌃⇧↑", toKeys: "⌥↑", category: codeEditor),
        GnomeShortcutDef(id: "moveLineDown", label: NSLocalizedString("Move Line Down", comment: ""), fromKeys: "⌃⇧↓", toKeys: "⌥↓", category: codeEditor)
    ]
    // swiftlint:enable line_length

    static func shortcuts(in category: String) -> [GnomeShortcutDef] {
        allShortcuts.filter { $0.category == category }
    }
}

// MARK: - Event handling

extension GnomeShortcutHandler {
    func handleKeyDown(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let hasControl = flags.contains(.maskControl)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let hasCommand = flags.contains(.maskCommand)

        if hasCommand { return false }

        if hasControl && !hasOption {
            return handleCtrlKey(event: event, keyCode: keyCode, flags: flags, hasShift: hasShift,
                                 isTerminal: KeyboardUtils.isTerminalApp())
        }

        if hasOption && !hasControl {
            return handleAltKey(event: event, keyCode: keyCode, flags: flags, hasShift: hasShift)
        }

        if !hasControl && !hasOption && !hasCommand && !hasShift {
            return handleNoModifierKey(event: event, keyCode: keyCode, flags: flags)
        }

        return false
    }

    // MARK: - Ctrl+key remaps

    private func handleCtrlKey(event: CGEvent, keyCode: Int64, flags: CGEventFlags,
                               hasShift: Bool, isTerminal: Bool) -> Bool {
        // Terminal Ctrl+Shift shortcuts (must be checked before passthrough)
        if isTerminal && hasShift,
           let id = Self.terminalShiftMap[keyCode], isEnabled(id) {
            return remap(event, keyCode, flags: flags, remove: [.maskControl, .maskShift], add: .maskCommand)
        }
        if isTerminal && Self.terminalPassthroughKeys.contains(keyCode) { return false }
        if keyCode == Self.keyTab { return false } // Ctrl+Tab already works on Mac

        // Special remaps (non-standard modifier swaps)
        if let result = handleCtrlSpecialKey(event: event, keyCode: keyCode, flags: flags, hasShift: hasShift) {
            return result
        }

        // Ctrl+Shift+key shortcuts (check before base Ctrl+key)
        if hasShift, let ids = Self.ctrlShiftMap[keyCode] {
            guard ids.contains(where: { isEnabled($0) }) else { return false }
            return remap(event, keyCode, flags: flags, remove: .maskControl, add: .maskCommand)
        }

        // General Ctrl → Cmd swap
        if let ids = Self.ctrlToCmdMap[keyCode], ids.contains(where: { isEnabled($0) }) {
            return remap(event, keyCode, flags: flags, remove: .maskControl, add: .maskCommand)
        }
        return false
    }

    // Each branch has different modifier transforms — can't be reduced to a lookup table.
    // swiftlint:disable:next cyclomatic_complexity
    private func handleCtrlSpecialKey(
        event: CGEvent, keyCode: Int64, flags: CGEventFlags, hasShift: Bool
    ) -> Bool? {
        if keyCode == Self.keyY && !hasShift && isEnabled("redo") { // Ctrl+Y → ⇧⌘Z
            return remap(event, Self.keyZ, flags: flags, remove: .maskControl, add: [.maskCommand, .maskShift])
        }
        if keyCode == Self.keyDelete && !hasShift && isEnabled("deleteWord") { // Ctrl+⌫ → ⌥⌫
            return remap(event, Self.keyDelete, flags: flags, remove: .maskControl, add: .maskAlternate)
        }
        if keyCode == Self.keyForwardDelete && !hasShift && isEnabled("forwardDeleteWord") { // Ctrl+⌦ → ⌥⌦
            return remap(event, Self.keyForwardDelete, flags: flags, remove: .maskControl, add: .maskAlternate)
        }
        if hasShift && keyCode == Self.keyLeft && isEnabled("selectWordLeft") { // Ctrl+Shift+← → ⌥⇧←
            return remap(event, keyCode, flags: flags, remove: .maskControl, add: .maskAlternate)
        }
        if hasShift && keyCode == Self.keyRight && isEnabled("selectWordRight") { // Ctrl+Shift+→ → ⌥⇧→
            return remap(event, keyCode, flags: flags, remove: .maskControl, add: .maskAlternate)
        }
        if keyCode == Self.keyLeft && isEnabled("wordLeft") { // Ctrl+← → ⌥←
            return remap(event, keyCode, flags: flags, remove: .maskControl, add: .maskAlternate)
        }
        if keyCode == Self.keyRight && isEnabled("wordRight") { // Ctrl+→ → ⌥→
            return remap(event, keyCode, flags: flags, remove: .maskControl, add: .maskAlternate)
        }
        if hasShift && keyCode == Self.keyDown && isEnabled("moveLineDown") { // Ctrl+Shift+↓ → ⌥↓
            return remap(event, keyCode, flags: flags, remove: [.maskControl, .maskShift], add: .maskAlternate)
        }
        if hasShift && keyCode == Self.keyUp && isEnabled("moveLineUp") { // Ctrl+Shift+↑ → ⌥↑
            return remap(event, keyCode, flags: flags, remove: [.maskControl, .maskShift], add: .maskAlternate)
        }
        if hasShift && keyCode == Self.keyDown && isEnabled("selectDown") { // Ctrl+Shift+↓ → Shift+↓
            return remap(event, keyCode, flags: flags, remove: .maskControl)
        }
        if hasShift && keyCode == Self.keyUp && isEnabled("selectUp") { // Ctrl+Shift+↑ → Shift+↑
            return remap(event, keyCode, flags: flags, remove: .maskControl)
        }
        if hasShift && keyCode == Self.keyI && isEnabled("devTools") { // Ctrl+Shift+I → ⌥⌘I
            return remap(event, Self.keyI, flags: flags, remove: [.maskControl, .maskShift],
                         add: [.maskCommand, .maskAlternate])
        }
        if keyCode == Self.keyH && !hasShift { // Ctrl+H → ⌥⌘F or ⌘Y
            if isEnabled("findReplace") {
                return remap(event, Self.keyF, flags: flags, remove: .maskControl,
                             add: [.maskCommand, .maskAlternate])
            }
            if isEnabled("viewHistory") {
                return remap(event, Self.keyY, flags: flags, remove: .maskControl, add: .maskCommand)
            }
        }
        return nil
    }

    // MARK: - Alt (Option) shortcuts

    private func handleAltKey(event: CGEvent, keyCode: Int64, flags: CGEventFlags, hasShift: Bool) -> Bool {
        if keyCode == Self.keyF4 && isEnabled("closeWindow") { // Alt+F4 → ⌘W
            return remap(event, Self.keyW, flags: flags, remove: .maskAlternate, add: .maskCommand)
        }
        if keyCode == Self.keyReturn && !hasShift && isEnabled("getInfo") { // Alt+Enter → ⌘I
            return remap(event, Self.keyI, flags: flags, remove: .maskAlternate, add: .maskCommand)
        }
        if keyCode == Self.keyL && !hasShift && isEnabled("lockScreen") { // Alt+L → ⌃⌘Q
            return remap(event, Self.keyQ, flags: flags, remove: .maskAlternate, add: [.maskCommand, .maskControl])
        }
        return false
    }

    // MARK: - No-modifier shortcuts

    private func handleNoModifierKey(event: CGEvent, keyCode: Int64, flags: CGEventFlags) -> Bool {
        if keyCode == Self.keyForwardDelete // ⌦ → ⌘⌫ (Move to Trash)
            && isEnabled("finderDelete") && !KeyboardUtils.isFocusedOnTextField() {
            return remap(event, Self.keyDelete, flags: flags, add: .maskCommand)
        }
        if keyCode == Self.keyF2 // F2 → Return (Rename)
            && isEnabled("rename") && !KeyboardUtils.isFocusedOnTextField() {
            return remap(event, Self.keyReturn, flags: flags, add: [])
        }
        if keyCode == Self.keyF11 && isEnabled("fullscreen") { // F11 → ⌃⌘F
            return remap(event, Self.keyF, flags: flags, add: [.maskCommand, .maskControl])
        }
        if keyCode == Self.keyF12 && isEnabled("devToolsF12") { // F12 → ⌥⌘I
            return remap(event, Self.keyI, flags: flags, add: [.maskCommand, .maskAlternate])
        }
        return false
    }
}
