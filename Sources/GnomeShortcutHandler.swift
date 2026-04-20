import Cocoa

struct GnomeShortcutDef: Identifiable, Hashable {
    let id: String
    let label: String
    let from: String
    let to: String
    let category: String
}

class GnomeShortcutHandler {
    static let categories = ["General", "Text Editing", "Finder", "Tabs & Windows", "Browsers", "Terminal", "Code Editor"]

    static let allShortcuts: [GnomeShortcutDef] = [
        // General
        GnomeShortcutDef(id: "copy", label: "Copy", from: "⌃C", to: "⌘C", category: "General"),
        GnomeShortcutDef(id: "cut", label: "Cut", from: "⌃X", to: "⌘X", category: "General"),
        GnomeShortcutDef(id: "paste", label: "Paste", from: "⌃V", to: "⌘V", category: "General"),
        GnomeShortcutDef(id: "undo", label: "Undo", from: "⌃Z", to: "⌘Z", category: "General"),
        GnomeShortcutDef(id: "redo", label: "Redo", from: "⌃Y", to: "⌘⇧Z", category: "General"),
        GnomeShortcutDef(id: "selectAll", label: "Select All", from: "⌃A", to: "⌘A", category: "General"),
        GnomeShortcutDef(id: "find", label: "Find", from: "⌃F", to: "⌘F", category: "General"),
        GnomeShortcutDef(id: "save", label: "Save", from: "⌃S", to: "⌘S", category: "General"),
        GnomeShortcutDef(id: "new", label: "New", from: "⌃N", to: "⌘N", category: "General"),
        GnomeShortcutDef(id: "print", label: "Print", from: "⌃P", to: "⌘P", category: "General"),
        GnomeShortcutDef(id: "lockScreen", label: "Lock Screen", from: "⌥L", to: "⌃⌘Q", category: "General"),
        // Finder
        GnomeShortcutDef(id: "getInfo", label: "Properties", from: "⌥↩", to: "⌘I", category: "Finder"),
        GnomeShortcutDef(id: "finderDelete", label: "Move to Trash", from: "⌦", to: "⌘⌫", category: "Finder"),
        GnomeShortcutDef(id: "rename", label: "Rename", from: "F2", to: "↩", category: "Finder"),
        // Text Editing
        GnomeShortcutDef(id: "bold", label: "Bold", from: "⌃B", to: "⌘B", category: "Text Editing"),
        GnomeShortcutDef(id: "underline", label: "Underline", from: "⌃U", to: "⌘U", category: "Text Editing"),
        GnomeShortcutDef(id: "deleteWord", label: "Delete Word", from: "⌃⌫", to: "⌥⌫", category: "Text Editing"),
        GnomeShortcutDef(id: "forwardDeleteWord", label: "Fwd Delete Word", from: "⌃⌦", to: "⌥⌦", category: "Text Editing"),
        GnomeShortcutDef(id: "wordLeft", label: "Word Left", from: "⌃←", to: "⌥←", category: "Text Editing"),
        GnomeShortcutDef(id: "wordRight", label: "Word Right", from: "⌃→", to: "⌥→", category: "Text Editing"),
        // Tabs & Windows
        GnomeShortcutDef(id: "newTab", label: "New Tab", from: "⌃T", to: "⌘T", category: "Tabs & Windows"),
        GnomeShortcutDef(id: "closeTab", label: "Close Tab", from: "⌃W", to: "⌘W", category: "Tabs & Windows"),
        GnomeShortcutDef(id: "reopenTab", label: "Reopen Tab", from: "⌃⇧T", to: "⌘⇧T", category: "Tabs & Windows"),
        GnomeShortcutDef(id: "closeWindow", label: "Close Window", from: "⌥F4", to: "⌘W", category: "Tabs & Windows"),
        GnomeShortcutDef(id: "addressBar", label: "Address Bar", from: "⌃L", to: "⌘L", category: "Browsers"),
        GnomeShortcutDef(id: "downloads", label: "Downloads", from: "⌃J", to: "⌘J", category: "Browsers"),
        // Browsers
        GnomeShortcutDef(id: "reload", label: "Reload", from: "⌃R", to: "⌘R", category: "Browsers"),
        GnomeShortcutDef(id: "devTools", label: "Developer Tools", from: "⌃⇧I", to: "⌘⌥I", category: "Browsers"),
        GnomeShortcutDef(id: "devToolsF12", label: "Developer Tools", from: "F12", to: "⌘⌥I", category: "Browsers"),
        GnomeShortcutDef(id: "viewHistory", label: "View History", from: "⌃H", to: "⌘Y", category: "Browsers"),
        GnomeShortcutDef(id: "viewSource", label: "View Source", from: "⌃U", to: "⌘U", category: "Browsers"),
        GnomeShortcutDef(id: "zoomIn", label: "Zoom In", from: "⌃+", to: "⌘+", category: "Browsers"),
        GnomeShortcutDef(id: "zoomOut", label: "Zoom Out", from: "⌃-", to: "⌘-", category: "Browsers"),
        GnomeShortcutDef(id: "zoomReset", label: "Reset Zoom", from: "⌃0", to: "⌘0", category: "Browsers"),
        GnomeShortcutDef(id: "fullscreen", label: "Full Screen", from: "F11", to: "⌃⌘F", category: "Browsers"),
        // Terminal
        GnomeShortcutDef(id: "termCopy", label: "Copy", from: "⌃⇧C", to: "⌘C", category: "Terminal"),
        GnomeShortcutDef(id: "termPaste", label: "Paste", from: "⌃⇧V", to: "⌘V", category: "Terminal"),
        GnomeShortcutDef(id: "termCloseTab", label: "Close Tab", from: "⌃⇧W", to: "⌘W", category: "Terminal"),
        GnomeShortcutDef(id: "termCloseWindow", label: "Close Window", from: "⌃⇧Q", to: "⌘Q", category: "Terminal"),
        // Code Editor
        GnomeShortcutDef(id: "settings", label: "Settings", from: "⌃,", to: "⌘,", category: "Code Editor"),
        GnomeShortcutDef(id: "toggleComment", label: "Toggle Comment", from: "⌃/", to: "⌘/", category: "Code Editor"),
        GnomeShortcutDef(id: "indent", label: "Indent", from: "⌃]", to: "⌘]", category: "Code Editor"),
        GnomeShortcutDef(id: "outdent", label: "Outdent", from: "⌃[", to: "⌘[", category: "Code Editor"),
        GnomeShortcutDef(id: "cmdEnter", label: "Run / Confirm", from: "⌃↩", to: "⌘↩", category: "Code Editor"),
        GnomeShortcutDef(id: "commandPalette", label: "Command Palette", from: "⌃⇧P", to: "⌘⇧P", category: "Code Editor"),
        GnomeShortcutDef(id: "deleteLine", label: "Delete Line", from: "⌃⇧K", to: "⌘⇧K", category: "Code Editor"),
        GnomeShortcutDef(id: "insertLineAbove", label: "Insert Line Above", from: "⌃⇧↩", to: "⌘⇧↩", category: "Code Editor"),
        GnomeShortcutDef(id: "hyperlink", label: "Insert Link", from: "⌃K", to: "⌘K", category: "Code Editor"),
        GnomeShortcutDef(id: "duplicate", label: "Duplicate", from: "⌃D", to: "⌘D", category: "Code Editor"),
        GnomeShortcutDef(id: "searchSelection", label: "Search Selection", from: "⌃E", to: "⌘E", category: "Code Editor"),
    ]

    static func shortcuts(in category: String) -> [GnomeShortcutDef] {
        allShortcuts.filter { $0.category == category }
    }

    // MARK: - Terminal detection

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable",
    ]

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

        let isTerminal = Self.isTerminalApp()

        // --- Ctrl+key remaps ---
        if hasControl && !hasOption {
            // Terminal Ctrl+Shift shortcuts (must be checked before passthrough)
            if isTerminal && hasShift,
               let id = Self.terminalShiftMap[keyCode], isEnabled(id)
            {
                var newFlags = flags
                newFlags.remove([.maskControl, .maskShift])
                newFlags.insert(.maskCommand)
                postKey(keyCode, flags: newFlags)
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
                postKey(Self.keyZ, flags: newFlags)
                return true
            }

            // Ctrl+Delete → Opt+Delete (Delete Word)
            if keyCode == Self.keyDelete && !hasShift && isEnabled("deleteWord") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                postKey(Self.keyDelete, flags: newFlags)
                return true
            }

            // Ctrl+Forward Delete → Opt+Forward Delete (Forward Delete Word)
            if keyCode == Self.keyForwardDelete && !hasShift && isEnabled("forwardDeleteWord") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                postKey(Self.keyForwardDelete, flags: newFlags)
                return true
            }

            // Ctrl+Left → Opt+Left (Word Left)
            if keyCode == Self.keyLeft && isEnabled("wordLeft") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                postKey(keyCode, flags: newFlags)
                return true
            }

            // Ctrl+Right → Opt+Right (Word Right)
            if keyCode == Self.keyRight && isEnabled("wordRight") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskAlternate)
                postKey(keyCode, flags: newFlags)
                return true
            }

            // Ctrl+Shift+I → Cmd+Opt+I (Developer Tools)
            if hasShift && keyCode == Self.keyI && isEnabled("devTools") {
                var newFlags = flags
                newFlags.remove([.maskControl, .maskShift])
                newFlags.insert([.maskCommand, .maskAlternate])
                postKey(Self.keyI, flags: newFlags)
                return true
            }

            // Ctrl+H → Cmd+Y (View History)
            if keyCode == Self.keyH && !hasShift && isEnabled("viewHistory") {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskCommand)
                postKey(Self.keyY, flags: newFlags)
                return true
            }

            // Ctrl+Shift+key shortcuts (check before base Ctrl+key)
            if hasShift, let id = Self.ctrlShiftMap[keyCode] {
                if isEnabled(id) {
                    var newFlags = flags
                    newFlags.remove(.maskControl)
                    newFlags.insert(.maskCommand)
                    postKey(keyCode, flags: newFlags)
                    return true
                }
                return false
            }

            // General Ctrl → Cmd swap
            if let ids = Self.ctrlToCmdMap[keyCode], ids.contains(where: { isEnabled($0) }) {
                var newFlags = flags
                newFlags.remove(.maskControl)
                newFlags.insert(.maskCommand)
                postKey(keyCode, flags: newFlags)
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
                postKey(Self.keyW, flags: newFlags)
                return true
            }

            // Alt+Enter → Cmd+I (Properties / Get Info)
            if keyCode == Self.keyReturn && !hasShift && isEnabled("getInfo") {
                var newFlags = flags
                newFlags.remove(.maskAlternate)
                newFlags.insert(.maskCommand)
                postKey(Self.keyI, flags: newFlags)
                return true
            }

            // Alt+L → Cmd+Ctrl+Q (Lock Screen)
            if keyCode == Self.keyL && !hasShift && isEnabled("lockScreen") {
                var newFlags = flags
                newFlags.remove(.maskAlternate)
                newFlags.insert([.maskCommand, .maskControl])
                postKey(Self.keyQ, flags: newFlags)
                return true
            }
        }

        // --- No-modifier shortcuts ---
        if !hasControl && !hasOption && !hasCommand && !hasShift {
            // Forward Delete → Cmd+Backspace (Move to Trash in Finder)
            if keyCode == Self.keyForwardDelete
                && isEnabled("finderDelete")
                && Self.isFinderApp()
                && !Self.isFocusedOnTextField()
            {
                var newFlags = flags
                newFlags.insert(.maskCommand)
                postKey(Self.keyDelete, flags: newFlags)
                return true
            }

            // F2 → Return (Rename in Finder)
            if keyCode == Self.keyF2
                && isEnabled("rename")
                && Self.isFinderApp()
                && !Self.isFocusedOnTextField()
            {
                postKey(Self.keyReturn, flags: flags)
                return true
            }

            // F11 → Ctrl+Cmd+F (Fullscreen)
            if keyCode == Self.keyF11 && isEnabled("fullscreen") {
                var newFlags = flags
                newFlags.insert([.maskCommand, .maskControl])
                postKey(Self.keyF, flags: newFlags)
                return true
            }

            // F12 → Cmd+Opt+I (Developer Tools)
            if keyCode == Self.keyF12 && isEnabled("devToolsF12") {
                var newFlags = flags
                newFlags.insert([.maskCommand, .maskAlternate])
                postKey(Self.keyI, flags: newFlags)
                return true
            }
        }

        return false
    }

    private func postKey(_ keyCode: Int64, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    private static func isTerminalApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return terminalBundleIDs.contains(bundleID)
    }

    private static func isFinderApp() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    private static func isFocusedOnTextField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }

        let axElement = element as! AXUIElement
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)
        guard let role = roleValue as? String else { return false }

        let textRoles: Set<String> = [
            kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
        ]
        return textRoles.contains(role)
    }
}
