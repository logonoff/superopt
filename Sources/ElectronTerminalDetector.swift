import Cocoa

/// Detects whether focus is inside the integrated terminal of an Electron-based code
/// editor, so terminal shortcut behaviour (plain Ctrl+C sending SIGINT rather than
/// being remapped to ⌘C, and so on) applies there as it does in a real terminal app.
///
/// Bundle ID alone can't answer this: VS Code is both a code editor and a terminal
/// host depending on which pane has focus, so the focused accessibility element has
/// to be inspected.
enum ElectronTerminalDetector {
    static let defaultsKey = "vscodeTerminalEnabled"

    /// Electron editors that ship an integrated terminal. A subset of
    /// `KeyboardUtils.codeEditorBundleIDs` — Zed and Sublime Text are native apps and
    /// need none of this.
    static let bundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium.VSCodium",
        "com.todesktop.230313mzl4w4u92" // Cursor
    ]

    /// VS Code labels the terminal's input "Terminal 3, zsh …" while the editor is an
    /// `AXTextArea` described as "The editor is not accessible at this time …", and
    /// other text fields (command palette, find) carry no such prefix. Matching the
    /// role and this prefix picks out the terminal and nothing else.
    ///
    /// The label comes from VS Code's own localisation, so this only matches an
    /// English VS Code UI. Failing to match just means the terminal is treated as a
    /// normal text field, which is the old behaviour.
    private static let terminalLabelPrefix = "Terminal "

    /// Only ever touched from the CGEvent tap callback, which runs on the main run
    /// loop, so no synchronisation is needed. Matches how the other KeyboardUtils
    /// helpers this sits behind are written.
    nonisolated(unsafe) private static var accessibilityEnabledPIDs: Set<pid_t> = []

    static func isFocusedOnIntegratedTerminal() -> Bool {
        guard UserDefaults.standard.bool(forKey: defaultsKey),
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleIDs.contains(bundleID)
        else { return false }

        let pid = app.processIdentifier
        enableAccessibility(for: pid)

        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid),
            kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef.flatMap(KeyboardUtils.toAXElement)
        else { return false }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef)
        guard roleRef as? String == kAXTextFieldRole else { return false }

        var descriptionRef: AnyObject?
        AXUIElementCopyAttributeValue(
            focused, kAXDescriptionAttribute as CFString, &descriptionRef)
        guard let label = descriptionRef as? String else { return false }
        return label.hasPrefix(terminalLabelPrefix)
    }

    /// Chromium apps build no accessibility tree until an assistive client asks for
    /// one, so the focused element query returns `kAXErrorNoValue` and the terminal
    /// can't be told from the editor. `AXManualAccessibility` is Chromium's opt-in for
    /// that — the same switch a screen reader would flip, and lighter than
    /// `AXEnhancedUserInterface`.
    ///
    /// Set once per process: the attribute reads back as `0` even once it has taken
    /// effect, so whether it is on has to be tracked here rather than queried.
    private static func enableAccessibility(for pid: pid_t) {
        guard !accessibilityEnabledPIDs.contains(pid) else { return }
        accessibilityEnabledPIDs.insert(pid)
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid),
            "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
