import Cocoa

enum KeyboardUtils {
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "io.alacritty",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
        "dev.warp.Warp-Stable"
    ]

    static let syntheticTag: Int64 = 0x4F5054 // "OPT"

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticTag
    }

    static func rewriteEvent(_ event: CGEvent, keyCode: Int64, flags: CGEventFlags) {
        event.setIntegerValueField(.keyboardEventKeycode, value: keyCode)
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
    }

    static func postKey(_ keyCode: Int64, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
        else { return }
        down.flags = flags
        keyUp.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
        down.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    /// Types a string as one keystroke carrying a Unicode payload. Used when the
    /// text to insert is known but the keys that would produce it are not — the
    /// buffered characters come from a keyboard layout that may not be the current
    /// one, so replaying key codes would mangle them.
    static func postText(_ text: String) {
        guard !text.isEmpty else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        var utf16 = Array(text.utf16)
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: src, virtualKey: 0, keyDown: isDown) else { return }
            event.keyboardSetUnicodeString(
                stringLength: utf16.count, unicodeString: &utf16)
            event.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            event.post(tap: .cgSessionEventTap)
        }
    }

    static func isTerminalApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        if terminalBundleIDs.contains(bundleID) { return true }
        return ElectronTerminalDetector.isFocusedOnIntegratedTerminal()
    }

    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
        "company.thebrowser.Browser" // Arc
    ]

    static func isBrowserApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return browserBundleIDs.contains(bundleID)
    }

    static let codeEditorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.vscodium.VSCodium",
        "dev.zed.Zed",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.jetbrains.intellij",
        "com.jetbrains.intellij.ce",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce",
        "com.jetbrains.CLion",
        "com.jetbrains.goland",
        "com.jetbrains.rider",
        "com.jetbrains.PhpStorm",
        "com.jetbrains.rubymine",
        "com.panic.Nova"
    ]

    static func isCodeEditorApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        // The integrated terminal is not the editor: editor shortcuts like Ctrl+/
        // (comment) mean nothing at a shell prompt.
        guard codeEditorBundleIDs.contains(bundleID) else { return false }
        return !ElectronTerminalDetector.isFocusedOnIntegratedTerminal()
    }

    static func isFinderApp() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    static func toAXElement(_ ref: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement) // swiftlint:disable:this force_cast
    }

    static func toAXValue(_ ref: AnyObject) -> AXValue? {
        guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue) // swiftlint:disable:this force_cast
    }

    private static let appServicesLib = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        RTLD_LAZY
    )

    // Private: _AXUIElementGetWindow maps an AXUIElement to its CGWindowID.
    // No public API bridges AX elements to CGWindowIDs — without this, matching
    // AX windows to compositor thumbnails requires fragile title-based heuristics.
    static let axGetWindow: (
        @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32
    )? = appServicesLib.flatMap { lib in
        dlsym(lib, "_AXUIElementGetWindow")
            .map { unsafeBitCast($0, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> Int32).self) }
    }

    static let systemWide = AXUIElementCreateSystemWide()

    static func primaryScreenHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func axWindowFrame(_ window: AXUIElement) -> CGRect {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let val = posRef.flatMap(toAXValue) { AXValueGetValue(val, .cgPoint, &pos) }
        if let val = sizeRef.flatMap(toAXValue) { AXValueGetValue(val, .cgSize, &size) }
        return CGRect(origin: pos, size: size)
    }

    static func cgRectToNS(_ rect: CGRect) -> NSRect {
        let height = primaryScreenHeight()
        return NSRect(x: rect.origin.x, y: height - rect.origin.y - rect.height,
                      width: rect.width, height: rect.height)
    }

    private static let missionControlTolerance: CGFloat = 1

    /// Mission Control is drawn by the `WindowManager` process, which puts a
    /// full-screen "Expose shield" above the normal window layer on every display
    /// (plus a Spaces Bar strip and transient highlight overlays). No
    /// `WindowManager` window is on screen when Mission Control is closed.
    ///
    /// Matched structurally — owner, layer and size — rather than by the
    /// `ExposeShieldWindow` window name, because `kCGWindowName` is only populated
    /// for other processes when the caller holds Screen Recording permission, which
    /// this app never requests. The Spaces Bar is a short strip, so requiring a
    /// full display's worth of both dimensions excludes it.
    ///
    /// Counting Dock windows does not work: the Dock is a single full-screen window
    /// that is identical whether or not Mission Control is open, and it has no
    /// on-screen window at all while the Dock is set to auto-hide.
    static func isMissionControlActive(_ windowList: [[String: Any]]) -> Bool {
        let screenSizes = NSScreen.screens.map(\.frame.size)
        return windowList.contains { info in
            guard info[kCGWindowOwnerName as String] as? String == "WindowManager",
                  let layer = info[kCGWindowLayer as String] as? Int, layer > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return false }
            return screenSizes.contains { size in
                rect.width >= size.width - missionControlTolerance
                    && rect.height >= size.height - missionControlTolerance
            }
        }
    }

    static func findAXWindow(pid: pid_t, windowID: UInt32) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
        guard let windows = ref as? [AXUIElement] else { return nil }
        if let getWindow = axGetWindow {
            for win in windows {
                var axWID: UInt32 = 0
                if getWindow(win, &axWID) == 0, axWID == windowID { return win }
            }
        }
        guard let list = CGWindowListCopyWindowInfo(
            [.optionAll], kCGNullWindowID) as? [[String: Any]],
              let title = list.first(where: {
                  $0[kCGWindowNumber as String] as? UInt32 == windowID
              })?[kCGWindowName as String] as? String
        else { return nil }
        for win in windows {
            var titleRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            if (titleRef as? String) == title { return win }
        }
        return nil
    }

    /// Brings a window to the front of its app and makes it the focused one.
    /// Does not activate the app — the caller decides whether to do that.
    static func raiseWindow(pid: pid_t, windowID: UInt32) {
        guard let window = findAXWindow(pid: pid, windowID: windowID) else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, window)
    }

    static func isFocusedOnTextField() -> Bool {
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            Self.systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success,
              let element = focusedElement,
              let axElement = toAXElement(element)
        else { return false }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)
        guard let role = roleValue as? String else { return false }

        let textRoles: Set<String> = [
            kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"
        ]
        return textRoles.contains(role)
    }

}
