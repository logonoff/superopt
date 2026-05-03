import Cocoa

@MainActor
class ZoomButtonHandler {
    /// Returns true if the event should be consumed.
    func handleClick(event: CGEvent) -> Bool {
        if event.flags.contains(.maskAlternate) { return false }

        let pos = event.location
        guard let button = fullScreenButton(at: pos),
              let window = windowForButton(button)
        else { return false }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != 0 else { return false }

        let filled = isWindowFilled(window, clickPoint: pos)
        let char = filled ? "R" : "F"
        return KeyboardUtils.pressTilingMenuItem(pid: pid, char: char)
    }

    // MARK: - AX helpers

    private func fullScreenButton(at pos: CGPoint) -> AXUIElement? {
        var axElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            KeyboardUtils.systemWide, Float(pos.x), Float(pos.y), &axElement)
        guard result == .success, let axElement else { return nil }

        var subroleValue: AnyObject?
        AXUIElementCopyAttributeValue(
            axElement, kAXSubroleAttribute as CFString, &subroleValue)
        guard let subrole = subroleValue as? String,
              subrole == "AXFullScreenButton" || subrole == "AXZoomButton"
        else { return nil }

        return axElement
    }

    private func windowForButton(_ button: AXUIElement) -> AXUIElement? {
        var current: AXUIElement = button
        for _ in 0..<10 {
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(
                current, kAXParentAttribute as CFString, &parentValue)
            guard let parent = parentValue,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { return nil }
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(
                parentElement, kAXRoleAttribute as CFString, &roleValue)
            if let role = roleValue as? String, role == kAXWindowRole {
                return parentElement
            }
            current = parentElement
        }
        return nil
    }

    private func isWindowFilled(_ window: AXUIElement, clickPoint: CGPoint) -> Bool {
        let nsClick = KeyboardUtils.cgRectToNS(CGRect(origin: clickPoint, size: .zero)).origin
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(nsClick) })
            ?? NSScreen.main else { return false }

        let winFrame = KeyboardUtils.axWindowFrame(window)
        let visible = screen.visibleFrame
        let fillFrame = CGRect(
            x: visible.origin.x,
            y: KeyboardUtils.primaryScreenHeight() - visible.origin.y - visible.height,
            width: visible.width, height: visible.height)

        return abs(winFrame.origin.x - fillFrame.origin.x) < 10
            && abs(winFrame.origin.y - fillFrame.origin.y) < 10
            && abs(winFrame.width - fillFrame.width) < 10
            && abs(winFrame.height - fillFrame.height) < 10
    }
}
