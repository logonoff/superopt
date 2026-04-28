import Cocoa

@MainActor
class MenuKeyHandler {
    private static let keyMenu: Int64 = 0x6E // Application/Menu key on PC keyboards

    func handleKeyDown(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.keyMenu,
              !event.flags.contains(.maskCommand),
              !event.flags.contains(.maskControl),
              !event.flags.contains(.maskAlternate),
              !event.flags.contains(.maskShift)
        else { return false }

        if showTextFieldContextMenu() { return true }

        let pos = event.location
        let src = CGEventSource(stateID: .hidSystemState)
        guard let mouseDown = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown,
                                      mouseCursorPosition: pos, mouseButton: .right),
              let mouseUp = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp,
                                    mouseCursorPosition: pos, mouseButton: .right)
        else { return false }
        mouseDown.post(tap: .cgSessionEventTap)
        mouseUp.post(tap: .cgSessionEventTap)
        return true
    }

    private func showTextFieldContextMenu() -> Bool {
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            KeyboardUtils.systemWide, kAXFocusedUIElementAttribute as CFString,
            &focusedRef) == .success,
              let element = focusedRef.flatMap(KeyboardUtils.toAXElement)
        else { return false }

        var savedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &savedRange) == .success
        else { return false }

        guard AXUIElementPerformAction(element, kAXShowMenuAction as CFString) == .success
        else { return false }

        if let range = savedRange {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, range)
        }
        return true
    }
}
