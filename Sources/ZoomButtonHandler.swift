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

        // A full-screen window has no previous size to fill or restore to, and the only
        // thing its green button does is leave full screen. Let the click through.
        if isFullScreen(window) { return false }

        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard pid != 0 else { return false }

        let filled = isWindowFilled(window, clickPoint: pos)
        let char = filled ? "R" : "F"

        // The Window menu's Fill / Return to Previous Size items act on the
        // app's key window, not on the window whose green button was
        // clicked, so the clicked window has to be made the focused one
        // first — and a background app brought forward, or the fill lands
        // on the wrong window and the click is gone.
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, window)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            NSRunningApplication(processIdentifier: pid)?.activate()
            pressWhenFront(pid: pid, window: window, char: char, attempts: 0)
            // Consumed even though the press is deferred: passing the click
            // through would give the app its native green-button behaviour
            // instead of Fill, and a synthetic re-post on a still-inactive
            // window is swallowed as bare activation (measured). The cost
            // is a rare swallowed click — when activation never completes,
            // or when the geometric fill test picks "Return to Previous
            // Size" for a manually-maximized window whose menu item is
            // disabled (measured: never-tiled windows disable it).
            return true
        }
        return KeyboardUtils.pressTilingMenuItem(pid: pid, char: char)
    }

    /// ⌘-menu items reach the app's own menu bar reliably once it is
    /// frontmost; a background app's activation is asynchronous, so the
    /// press waits for it (the SnapAssistActions pattern).
    private func pressWhenFront(
        pid: pid_t, window: AXUIElement, char: String, attempts: Int
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid || attempts >= 10 {
            // Activation makes the app's own recorded key window key, which
            // is not necessarily the one whose button was clicked — re-apply
            // the raise right before pressing, as SnapAssistActions does.
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, window)
            _ = KeyboardUtils.pressTilingMenuItem(pid: pid, char: char)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pressWhenFront(pid: pid, window: window, char: char, attempts: attempts + 1)
        }
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

    /// `AXFullScreen` is an undocumented AX attribute on window elements, true while the window
    /// occupies a full-screen space. No public API reports that for another app's window:
    /// `NSWindow.isZoomed` and the full-screen style mask cover this process only, and a
    /// full-screen window is indistinguishable from a display-sized one in the window list.
    private func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(
            window, "AXFullScreen" as CFString, &value) == .success
        else { return false }
        return value as? Bool ?? false
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

        // One-sided comparisons with tolerance, not abs() equality: a window
        // can extend past visibleFrame into the menu-bar strip or Dock area
        // and still be filled (the same convention as Tile Assist detection
        // and MenuBarBackground's fill test).
        let tolerance: CGFloat = 10
        return winFrame.minX <= fillFrame.minX + tolerance
            && winFrame.minY <= fillFrame.minY + tolerance
            && winFrame.maxX >= fillFrame.maxX - tolerance
            && winFrame.maxY >= fillFrame.maxY - tolerance
    }
}
