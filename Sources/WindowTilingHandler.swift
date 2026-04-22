import Cocoa

class WindowTilingHandler {
    private static let tilingModifier = 28 // fn+Ctrl modifier value in AX menu items

    func handleKeyDown(event: CGEvent) -> Bool {
        let flags = event.flags
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskShift)
        else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case 0x7B: return pressTileMenuItem(virtualKey: 0x7B)    // Left → Left Half
        case 0x7C: return pressTileMenuItem(virtualKey: 0x7C)    // Right → Right Half
        case 0x7E: return pressTileMenuItem(char: "F")           // Up → Fill
        case 0x7D: return pressTileMenuItem(char: "R")           // Down → Return to Previous Size
        default: return false
        }
    }

    // MARK: - AX menu search

    private func pressTileMenuItem(virtualKey: Int64) -> Bool {
        findAndPress(matching: { element in
            var vkValue: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, "AXMenuItemCmdVirtualKey" as CFString, &vkValue
            ) == .success, (vkValue as? Int64) == virtualKey else { return false }
            return hasModifier(element)
        })
    }

    private func pressTileMenuItem(char: String) -> Bool {
        findAndPress(matching: { element in
            var charValue: AnyObject?
            guard AXUIElementCopyAttributeValue(
                element, "AXMenuItemCmdChar" as CFString, &charValue
            ) == .success, (charValue as? String) == char else { return false }
            return hasModifier(element)
        })
    }

    private func hasModifier(_ element: AXUIElement) -> Bool {
        var modValue: AnyObject?
        AXUIElementCopyAttributeValue(element, "AXMenuItemCmdModifiers" as CFString, &modValue)
        return (modValue as? Int) == Self.tilingModifier
    }

    private func findAndPress(matching predicate: (AXUIElement) -> Bool) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var menuBarValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXMenuBarAttribute as CFString, &menuBarValue
        ) == .success,
              let menuBar = menuBarValue.flatMap(KeyboardUtils.toAXElement)
        else { return false }
        return search(in: menuBar, matching: predicate, depth: 5)
    }

    private func search(
        in element: AXUIElement, matching predicate: (AXUIElement) -> Bool, depth: Int
    ) -> Bool {
        guard depth > 0 else { return false }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenValue
        ) == .success, let children = childrenValue as? [AXUIElement] else { return false }

        for child in children {
            if predicate(child) {
                AXUIElementPerformAction(child, kAXPressAction as CFString)
                return true
            }
            if search(in: child, matching: predicate, depth: depth - 1) {
                return true
            }
        }
        return false
    }
}
