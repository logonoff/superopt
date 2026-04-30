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

    static func isTerminalApp() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return terminalBundleIDs.contains(bundleID)
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
        return codeEditorBundleIDs.contains(bundleID)
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

    static func isMissionControlActive(_ windowList: [[String: Any]]) -> Bool {
        let dockOverlays = windowList.filter { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int
            else { return false }
            return owner == "Dock" && layer > 0
        }.count
        return dockOverlays > 1
    }

    // MARK: - AX menu item search

    private static let tilingModifier = 28

    static func pressTilingMenuItem(pid: pid_t, char: String) -> Bool {
        pressMenuItem(pid: pid, matching: { element in
            var charValue: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, "AXMenuItemCmdChar" as CFString, &charValue
            ) == .success, (charValue as? String) == char else { return false }
            return hasTilingModifier(element)
        })
    }

    static func pressTilingMenuItem(pid: pid_t, virtualKey: Int64) -> Bool {
        pressMenuItem(pid: pid, matching: { element in
            var vkValue: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, "AXMenuItemCmdVirtualKey" as CFString, &vkValue
            ) == .success, (vkValue as? Int64) == virtualKey else { return false }
            return hasTilingModifier(element)
        })
    }

    private static func hasTilingModifier(_ element: AXUIElement) -> Bool {
        var modValue: AnyObject?
        AXUIElementCopyAttributeValue(
            element, "AXMenuItemCmdModifiers" as CFString, &modValue)
        return (modValue as? Int) == tilingModifier
    }

    static func pressArrangeMenuItem(pid: pid_t, virtualKey: Int64) -> Bool {
        pressMenuItem(pid: pid, matching: { element in
            var vkValue: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, "AXMenuItemCmdVirtualKey" as CFString, &vkValue
            ) == .success, (vkValue as? Int64) == virtualKey else { return false }
            return hasArrangeModifier(element)
        })
    }

    private static let arrangeModifier = 29

    private static func hasArrangeModifier(_ element: AXUIElement) -> Bool {
        var modValue: AnyObject?
        AXUIElementCopyAttributeValue(
            element, "AXMenuItemCmdModifiers" as CFString, &modValue)
        return (modValue as? Int) == arrangeModifier
    }

    private static func pressMenuItem(
        pid: pid_t, matching predicate: (AXUIElement) -> Bool
    ) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXMenuBarAttribute as CFString, &menuBarRef
        ) == .success,
              let menuBar = menuBarRef.flatMap(toAXElement)
        else { return false }
        return searchMenu(in: menuBar, matching: predicate, depth: 5)
    }

    private static func searchMenu(
        in element: AXUIElement,
        matching predicate: (AXUIElement) -> Bool, depth: Int
    ) -> Bool {
        guard depth > 0 else { return false }
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success,
              let children = childrenRef as? [AXUIElement] else { return false }
        for child in children {
            if predicate(child) {
                AXUIElementPerformAction(child, kAXPressAction as CFString)
                return true
            }
            if searchMenu(in: child, matching: predicate, depth: depth - 1) {
                return true
            }
        }
        return false
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
