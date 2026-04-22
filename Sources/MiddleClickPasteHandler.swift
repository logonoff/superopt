import Cocoa

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
        let systemWide = AXUIElementCreateSystemWide()
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(pos.x), Float(pos.y), &axElement
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
        let systemWide = AXUIElementCreateSystemWide()
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(pos.x), Float(pos.y), &axElement
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

    private func openNewWindow(of appURL: URL) {
        let bundleID = Bundle(url: appURL)?.bundleIdentifier
        let isRunning = bundleID != nil
            && NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if isRunning {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    KeyboardUtils.postKey(0x2D, flags: .maskCommand) // ⌘N
                }
            }
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }
}
