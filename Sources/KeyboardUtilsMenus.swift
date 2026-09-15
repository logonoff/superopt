import Cocoa

// Pressing a menu item is how window tiling is triggered: the Window menu's
// Fill / Left / Right / Return to Previous Size items have no public API and no
// stable titles across locales, so they are matched by their key equivalent.
extension KeyboardUtils {
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
}
