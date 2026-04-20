import Cocoa

struct GnomeShortcutDef: Identifiable, Hashable {
    let id: String
    let label: String
    let from: String
    let to: String
    let category: String
}

class GnomeShortcutHandler {
    // genstrings requires literal NSLocalizedString calls — can't use a wrapper function
    private static let general = NSLocalizedString("General", comment: "Shortcut category")
    private static let textEditing = NSLocalizedString("Text Editing", comment: "Shortcut category")
    private static let finder = NSLocalizedString("Finder", comment: "Shortcut category")
    private static let tabsWindows = NSLocalizedString("Tabs & Windows", comment: "Shortcut category")
    private static let browsers = NSLocalizedString("Browsers", comment: "Shortcut category")
    private static let terminal = NSLocalizedString("Terminal", comment: "Shortcut category")
    private static let codeEditor = NSLocalizedString("Code Editor", comment: "Shortcut category")

    static let categories = [general, textEditing, finder, tabsWindows, browsers, terminal, codeEditor]

    // swiftlint:disable line_length
    static let allShortcuts: [GnomeShortcutDef] = [
        GnomeShortcutDef(id: "copy",       label: NSLocalizedString("Copy", comment: ""),        from: "⌃C",  to: "⌘C",   category: general),
        GnomeShortcutDef(id: "cut",        label: NSLocalizedString("Cut", comment: ""),          from: "⌃X",  to: "⌘X",   category: general),
        GnomeShortcutDef(id: "paste",      label: NSLocalizedString("Paste", comment: ""),        from: "⌃V",  to: "⌘V",   category: general),
        GnomeShortcutDef(id: "undo",       label: NSLocalizedString("Undo", comment: ""),         from: "⌃Z",  to: "⌘Z",   category: general),
        GnomeShortcutDef(id: "redo",       label: NSLocalizedString("Redo", comment: ""),         from: "⌃Y",  to: "⌘⇧Z",  category: general),
        GnomeShortcutDef(id: "selectAll",  label: NSLocalizedString("Select All", comment: ""),   from: "⌃A",  to: "⌘A",   category: general),
        GnomeShortcutDef(id: "find",       label: NSLocalizedString("Find", comment: ""),         from: "⌃F",  to: "⌘F",   category: general),
        GnomeShortcutDef(id: "save",       label: NSLocalizedString("Save", comment: ""),         from: "⌃S",  to: "⌘S",   category: general),
        GnomeShortcutDef(id: "new",        label: NSLocalizedString("New", comment: ""),          from: "⌃N",  to: "⌘N",   category: general),
        GnomeShortcutDef(id: "print",      label: NSLocalizedString("Print", comment: ""),        from: "⌃P",  to: "⌘P",   category: general),
        GnomeShortcutDef(id: "lockScreen", label: NSLocalizedString("Lock Screen", comment: ""),  from: "⌥L",  to: "⌃⌘Q",  category: general),

        GnomeShortcutDef(id: "getInfo",      label: NSLocalizedString("Properties", comment: ""),    from: "⌥↩", to: "⌘I",  category: finder),
        GnomeShortcutDef(id: "finderDelete", label: NSLocalizedString("Move to Trash", comment: ""), from: "⌦",  to: "⌘⌫",  category: finder),
        GnomeShortcutDef(id: "rename",       label: NSLocalizedString("Rename", comment: ""),        from: "F2", to: "↩",    category: finder),

        GnomeShortcutDef(id: "bold",              label: NSLocalizedString("Bold", comment: ""),            from: "⌃B", to: "⌘B", category: textEditing),
        GnomeShortcutDef(id: "underline",         label: NSLocalizedString("Underline", comment: ""),       from: "⌃U", to: "⌘U", category: textEditing),
        GnomeShortcutDef(id: "deleteWord",        label: NSLocalizedString("Delete Word", comment: ""),     from: "⌃⌫", to: "⌥⌫", category: textEditing),
        GnomeShortcutDef(id: "forwardDeleteWord", label: NSLocalizedString("Fwd Delete Word", comment: ""), from: "⌃⌦", to: "⌥⌦", category: textEditing),
        GnomeShortcutDef(id: "wordLeft",          label: NSLocalizedString("Word Left", comment: ""),       from: "⌃←", to: "⌥←", category: textEditing),
        GnomeShortcutDef(id: "wordRight",         label: NSLocalizedString("Word Right", comment: ""),      from: "⌃→", to: "⌥→", category: textEditing),

        GnomeShortcutDef(id: "newTab",      label: NSLocalizedString("New Tab", comment: ""),      from: "⌃T",  to: "⌘T",  category: tabsWindows),
        GnomeShortcutDef(id: "closeTab",    label: NSLocalizedString("Close Tab", comment: ""),    from: "⌃W",  to: "⌘W",  category: tabsWindows),
        GnomeShortcutDef(id: "reopenTab",   label: NSLocalizedString("Reopen Tab", comment: ""),   from: "⌃⇧T", to: "⌘⇧T", category: tabsWindows),
        GnomeShortcutDef(id: "closeWindow", label: NSLocalizedString("Close Window", comment: ""), from: "⌥F4", to: "⌘W",  category: tabsWindows),

        GnomeShortcutDef(id: "addressBar",  label: NSLocalizedString("Address Bar", comment: ""),      from: "⌃L",  to: "⌘L",   category: browsers),
        GnomeShortcutDef(id: "downloads",   label: NSLocalizedString("Downloads", comment: ""),        from: "⌃J",  to: "⌘J",   category: browsers),
        GnomeShortcutDef(id: "reload",      label: NSLocalizedString("Reload", comment: ""),           from: "⌃R",  to: "⌘R",   category: browsers),
        GnomeShortcutDef(id: "devTools",    label: NSLocalizedString("Developer Tools", comment: ""),  from: "⌃⇧I", to: "⌘⌥I",  category: browsers),
        GnomeShortcutDef(id: "devToolsF12", label: NSLocalizedString("Developer Tools", comment: ""),  from: "F12", to: "⌘⌥I",   category: browsers),
        GnomeShortcutDef(id: "viewHistory", label: NSLocalizedString("View History", comment: ""),     from: "⌃H",  to: "⌘Y",   category: browsers),
        GnomeShortcutDef(id: "viewSource",  label: NSLocalizedString("View Source", comment: ""),      from: "⌃U",  to: "⌘U",   category: browsers),
        GnomeShortcutDef(id: "zoomIn",      label: NSLocalizedString("Zoom In", comment: ""),          from: "⌃+",  to: "⌘+",   category: browsers),
        GnomeShortcutDef(id: "zoomOut",     label: NSLocalizedString("Zoom Out", comment: ""),         from: "⌃-",  to: "⌘-",   category: browsers),
        GnomeShortcutDef(id: "zoomReset",   label: NSLocalizedString("Reset Zoom", comment: ""),       from: "⌃0",  to: "⌘0",   category: browsers),
        GnomeShortcutDef(id: "fullscreen",  label: NSLocalizedString("Full Screen", comment: ""),      from: "F11", to: "⌃⌘F",   category: browsers),

        GnomeShortcutDef(id: "termCopy",        label: NSLocalizedString("Copy", comment: ""),         from: "⌃⇧C", to: "⌘C", category: terminal),
        GnomeShortcutDef(id: "termPaste",       label: NSLocalizedString("Paste", comment: ""),        from: "⌃⇧V", to: "⌘V", category: terminal),
        GnomeShortcutDef(id: "termCloseTab",    label: NSLocalizedString("Close Tab", comment: ""),    from: "⌃⇧W", to: "⌘W", category: terminal),
        GnomeShortcutDef(id: "termCloseWindow", label: NSLocalizedString("Close Window", comment: ""), from: "⌃⇧Q", to: "⌘Q", category: terminal),

        GnomeShortcutDef(id: "settings",        label: NSLocalizedString("Settings", comment: ""),          from: "⌃,",  to: "⌘,",   category: codeEditor),
        GnomeShortcutDef(id: "toggleComment",   label: NSLocalizedString("Toggle Comment", comment: ""),    from: "⌃/",  to: "⌘/",   category: codeEditor),
        GnomeShortcutDef(id: "indent",          label: NSLocalizedString("Indent", comment: ""),            from: "⌃]",  to: "⌘]",   category: codeEditor),
        GnomeShortcutDef(id: "outdent",         label: NSLocalizedString("Outdent", comment: ""),           from: "⌃[",  to: "⌘[",   category: codeEditor),
        GnomeShortcutDef(id: "cmdEnter",        label: NSLocalizedString("Run / Confirm", comment: ""),     from: "⌃↩",  to: "⌘↩",   category: codeEditor),
        GnomeShortcutDef(id: "commandPalette",  label: NSLocalizedString("Command Palette", comment: ""),   from: "⌃⇧P", to: "⌘⇧P",  category: codeEditor),
        GnomeShortcutDef(id: "deleteLine",      label: NSLocalizedString("Delete Line", comment: ""),       from: "⌃⇧K", to: "⌘⇧K",  category: codeEditor),
        GnomeShortcutDef(id: "insertLineAbove", label: NSLocalizedString("Insert Line Above", comment: ""), from: "⌃⇧↩", to: "⌘⇧↩",  category: codeEditor),
        GnomeShortcutDef(id: "hyperlink",       label: NSLocalizedString("Insert Link", comment: ""),       from: "⌃K",  to: "⌘K",   category: codeEditor),
        GnomeShortcutDef(id: "duplicate",       label: NSLocalizedString("Duplicate", comment: ""),         from: "⌃D",  to: "⌘D",   category: codeEditor),
        GnomeShortcutDef(id: "searchSelection", label: NSLocalizedString("Search Selection", comment: ""),  from: "⌃E",  to: "⌘E",   category: codeEditor),
    ]
    // swiftlint:enable line_length

    static func shortcuts(in category: String) -> [GnomeShortcutDef] {
        allShortcuts.filter { $0.category == category }
    }

    // MARK: - Terminal detection

    private static let terminalPassthroughKeys: Set<Int64> = [
        0x08, // C - interrupt
        0x02, // D - EOF
        0x0E, // E - end of line
        0x25, // L - clear
        0x20, // U - delete to start of line
        0x0D, // W - delete previous word
        0x06, // Z - suspend
    ]

    // Ctrl+Shift+key in terminal apps → Cmd+key (removes both Ctrl and Shift)
    private static let terminalShiftMap: [Int64: String] = [
        0x08: "termCopy",        // C
        0x09: "termPaste",       // V
        0x0D: "termCloseTab",    // W
        0x0C: "termCloseWindow", // Q
    ]

    // MARK: - Key code maps

    // Ctrl+Shift+key shortcuts with their own toggle (checked before base Ctrl+key)
    private static let ctrlShiftMap: [Int64: String] = [
        0x11: "reopenTab",       // T
        0x23: "commandPalette",  // P
        0x28: "deleteLine",      // K
        0x24: "insertLineAbove", // Return
    ]

    // Ctrl+key → Cmd+key (simple modifier swap)
    private static let ctrlToCmdMap: [Int64: [String]] = [
        0x00: ["selectAll"],       // A
        0x0B: ["bold"],            // B
        0x08: ["copy"],            // C
        0x02: ["duplicate"],       // D
        0x0E: ["searchSelection"], // E
        0x03: ["find"],            // F
        0x26: ["downloads"],       // J
        0x28: ["hyperlink"],       // K
        0x25: ["addressBar"],      // L
        0x2D: ["new"],             // N
        0x23: ["print"],           // P
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
        0x24: ["cmdEnter"],        // Return
    ]

    // MARK: - Key codes

    private static let keyY: Int64 = 0x10
    private static let keyZ: Int64 = 0x06
    private static let keyDelete: Int64 = 0x33
    private static let keyLeft: Int64 = 0x7B
    private static let keyRight: Int64 = 0x7C
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

    init() {
        reloadSettings()
    }

    func reloadSettings() {
        disabledShortcuts = Set(
            UserDefaults.standard.stringArray(forKey: "gnomeDisabledShortcuts") ?? [])
    }

    private func isEnabled(_ id: String) -> Bool {
        !disabledShortcuts.contains(id)
    }

    // MARK: - Event handling

    /// Returns true if the event was consumed.
    func handleKeyDown(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let hasControl = flags.contains(.maskControl)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let hasCommand = flags.contains(.maskCommand)

        if hasCommand { return false }

        let isTerminal = KeyboardUtils.isTerminalApp()

        // --- Ctrl+key remaps ---
        if hasControl && !hasOption {
            // Terminal Ctrl+Shift shortcuts (must be checked before passthrough)
            if isTerminal && hasShift,
               let id = Self.terminalShiftMap[keyCode], isEnabled(id)
            {
                var newFlags = flags
                newFlags.remove([.maskControl, .maskShift])
                newFlags.insert(.maskCommand)
                KeyboardUtils.postKey(keyCode, flags: newFlags)
                return true
            }

            if isTerminal && Self.terminalPassthroughKeys.contains(keyCode) {
                return false
            }

            // Ctrl+Tab already works correctly on Mac
            if keyCode == Self.keyTab { return false }

            // Ctrl+Y → Cmd+Shift+Z (Redo)
            if keyCode == Self.keyY && !hasShift && isEnabled("redo") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert([.maskCommand, .maskShift])
                KeyboardUtils.postKey(Self.keyZ, flags: newFlags)
                return true
            }

            // Ctrl+Delete → Opt+Delete (Delete Word)
            if keyCode == Self.keyDelete && !hasShift && isEnabled("deleteWord") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                KeyboardUtils.postKey(Self.keyDelete, flags: newFlags)
                return true
            }

            // Ctrl+Forward Delete → Opt+Forward Delete (Forward Delete Word)
            if keyCode == Self.keyForwardDelete && !hasShift && isEnabled("forwardDeleteWord") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                KeyboardUtils.postKey(Self.keyForwardDelete, flags: newFlags)
                return true
            }

            // Ctrl+Left → Opt+Left (Word Left)
            if keyCode == Self.keyLeft && isEnabled("wordLeft") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                KeyboardUtils.postKey(keyCode, flags: newFlags)
                return true
            }

            // Ctrl+Right → Opt+Right (Word Right)
            if keyCode == Self.keyRight && isEnabled("wordRight") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                KeyboardUtils.postKey(keyCode, flags: newFlags)
                return true
            }

            // Ctrl+Shift+I → Cmd+Opt+I (Developer Tools)
            if hasShift && keyCode == Self.keyI && isEnabled("devTools") {
                var newFlags = flags
                newFlags.remove([.maskControl, .maskShift])
                newFlags.insert([.maskCommand, .maskAlternate])
                KeyboardUtils.postKey(Self.keyI, flags: newFlags)
                return true
            }

            // Ctrl+H → Cmd+Y (View History)
            if keyCode == Self.keyH && !hasShift && isEnabled("viewHistory") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskCommand)
                KeyboardUtils.postKey(Self.keyY, flags: newFlags)
                return true
            }

            // Ctrl+Shift+key shortcuts (check before base Ctrl+key)
            if hasShift, let id = Self.ctrlShiftMap[keyCode] {
                if isEnabled(id) {
                    var newFlags = flags
                    newFlags.remove(.maskControl)
                    newFlags.insert(.maskCommand)
                    KeyboardUtils.postKey(keyCode, flags: newFlags)
                    return true
                }
                return false
            }

            // General Ctrl → Cmd swap
            if let ids = Self.ctrlToCmdMap[keyCode], ids.contains(where: { isEnabled($0) }) {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskCommand)
                KeyboardUtils.postKey(keyCode, flags: newFlags)
                return true
            }
        }

        // --- Alt (Option) shortcuts ---
        if hasOption && !hasControl {
            // Alt+F4 → Cmd+W (Close Window)
            if keyCode == Self.keyF4 && isEnabled("closeWindow") {
                var newFlags = flags
                newFlags.remove(.maskAlternate)
                newFlags.insert(.maskCommand)
                KeyboardUtils.postKey(Self.keyW, flags: newFlags)
                return true
            }

            // Alt+Enter → Cmd+I (Properties / Get Info)
            if keyCode == Self.keyReturn && !hasShift && isEnabled("getInfo") {
                var newFlags = flags
                newFlags.remove(.maskAlternate)
                newFlags.insert(.maskCommand)
                KeyboardUtils.postKey(Self.keyI, flags: newFlags)
                return true
            }

            // Alt+L → Cmd+Ctrl+Q (Lock Screen)
            if keyCode == Self.keyL && !hasShift && isEnabled("lockScreen") {
                var newFlags = flags
                newFlags.remove(.maskAlternate)
                newFlags.insert([.maskCommand, .maskControl])
                KeyboardUtils.postKey(Self.keyQ, flags: newFlags)
                return true
            }
        }

        // --- No-modifier shortcuts ---
        if !hasControl && !hasOption && !hasCommand && !hasShift {
            // Forward Delete → Cmd+Backspace (Move to Trash in Finder)
            if keyCode == Self.keyForwardDelete
                && isEnabled("finderDelete")
                && KeyboardUtils.isFinderApp()
                && !KeyboardUtils.isFocusedOnTextField()
            {
                var newFlags = flags
                newFlags.insert(.maskCommand)
                KeyboardUtils.postKey(Self.keyDelete, flags: newFlags)
                return true
            }

            // F2 → Return (Rename in Finder)
            if keyCode == Self.keyF2
                && isEnabled("rename")
                && KeyboardUtils.isFinderApp()
                && !KeyboardUtils.isFocusedOnTextField()
            {
                KeyboardUtils.postKey(Self.keyReturn, flags: flags)
                return true
            }

            // F11 → Ctrl+Cmd+F (Fullscreen)
            if keyCode == Self.keyF11 && isEnabled("fullscreen") {
                var newFlags = flags
                newFlags.insert([.maskCommand, .maskControl])
                KeyboardUtils.postKey(Self.keyF, flags: newFlags)
                return true
            }

            // F12 → Cmd+Opt+I (Developer Tools)
            if keyCode == Self.keyF12 && isEnabled("devToolsF12") {
                var newFlags = flags
                newFlags.insert([.maskCommand, .maskAlternate])
                KeyboardUtils.postKey(Self.keyI, flags: newFlags)
                return true
            }
        }

        return false
    }

}
