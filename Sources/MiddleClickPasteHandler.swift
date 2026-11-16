import Cocoa

@MainActor
class MiddleClickPasteHandler {
    /// Returns true if the event was consumed.
    func handleMouseDown(event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNumber == 2 else { return false }

        let (onDock, appURL) = dockAppInfo(at: event.location)
        if onDock {
            if let appURL { openNewWindow(of: appURL) }
            return true
        }

        // Only paste if the click target is a text field
        guard isTextFieldAt(event.location) else { return false }

        // Pass through the click (focuses text field, positions cursor),
        // then paste if a text field ended up focused
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if KeyboardUtils.isFocusedOnTextField() {
                KeyboardUtils.postKey(0x09, flags: .maskCommand) // ⌘V
            }
        }
        return false
    }

    // MARK: - Hit testing

    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"
    ]

    private func isTextFieldAt(_ pos: CGPoint) -> Bool {
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            KeyboardUtils.systemWide, Float(pos.x), Float(pos.y), &axElement
        ) == .success, let element = axElement else { return false }

        var current = element
        for _ in 0..<5 {
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleValue)
            if let role = roleValue as? String, Self.textRoles.contains(role) { return true }
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard let parent = parentValue,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { break }
            current = parentElement
        }
        return false
    }

    // MARK: - Dock detection

    private func dockAppInfo(at pos: CGPoint) -> (onDock: Bool, appURL: URL?) {
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            KeyboardUtils.systemWide, Float(pos.x), Float(pos.y), &axElement
        ) == .success, let element = axElement else {
            return (false, nil)
        }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first, pid == dockApp.processIdentifier else {
            return (false, nil)
        }

        // Traverse up to find the dock item (click may land on a child element)
        var current = element
        for _ in 0..<5 {
            var subroleValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subroleValue)
            if let subrole = subroleValue as? String, subrole == "AXApplicationDockItem" {
                var urlValue: AnyObject?
                AXUIElementCopyAttributeValue(current, kAXURLAttribute as CFString, &urlValue)
                if let url = urlValue as? URL { return (true, url) }
                if let str = urlValue as? String { return (true, URL(string: str)) }
                return (true, nil)
            }
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard let parent = parentValue,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { break }
            current = parentElement
        }
        return (true, nil)
    }

    // MARK: - New window

    /// Time for the app to come forward before ⌘N is aimed at it.
    private static let activationDelay: TimeInterval = 0.15
    /// How long a reopened app is given to put up a window of its own.
    private static let reopenGrace: TimeInterval = 0.6

    private func openNewWindow(of appURL: URL) {
        let bundleID = Bundle(url: appURL)?.bundleIdentifier
        let pid = bundleID.flatMap { id in
            NSWorkspace.shared.runningApplications
                .first { $0.bundleIdentifier == id }?.processIdentifier
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        guard let pid else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return
        }

        // Activating an app with no windows left makes AppKit's reopen handling
        // open one, so a ⌘N on top of that is a second window.
        let hadWindows = Self.windowCount(pid: pid) > 0
        let activationDelay = Self.activationDelay
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
                if hadWindows {
                    Self.postNewWindow()
                } else {
                    Self.postNewWindowIfReopenDidNot(
                        pid: pid, deadline: Date() + Self.reopenGrace)
                }
            }
        }
    }

    /// An app that answers a reopen with a window of its own needs nothing
    /// further; one that ignores it still gets its ⌘N, just late.
    private static func postNewWindowIfReopenDidNot(pid: pid_t, deadline: Date) {
        guard windowCount(pid: pid) == 0 else { return }
        guard Date() < deadline else { return postNewWindow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            postNewWindowIfReopenDidNot(pid: pid, deadline: deadline)
        }
    }

    private static func postNewWindow() {
        KeyboardUtils.postKey(0x2D, flags: .maskCommand) // ⌘N
    }

    /// The windows the app has, minimized and hidden ones included. Read through
    /// the accessibility API rather than `CGWindowListCopyWindowInfo`, which only
    /// lists what is on screen and would call a minimized window no window at all.
    /// The role check drops Finder's desktop, which is in the list as an
    /// `AXScrollArea`.
    private static func windowCount(pid: pid_t) -> Int {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value
        ) == .success, let windows = value as? [AXUIElement] else { return 0 }
        return windows.filter { window in
            var role: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &role)
            return role as? String == kAXWindowRole
        }.count
    }
}
