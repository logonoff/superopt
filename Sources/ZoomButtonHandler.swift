import Cocoa

class ZoomButtonHandler {
    private var savedFrames: [String: CGRect] = [:]

    /// Returns true if the event should be consumed.
    func handleClick(event: CGEvent) -> Bool {
        if event.flags.contains(.maskAlternate) { return false }

        let pos = event.location
        guard let button = fullScreenButton(at: pos),
              let window = windowForButton(button)
        else { return false }

        let windowFrame = getFrame(of: window)
        let screen = screenForPoint(pos)
        let fillFrame = visibleFrameInAXCoords(screen: screen)
        let key = windowKey(window)

        let isZoomed = abs(windowFrame.origin.x - fillFrame.origin.x) < 10
            && abs(windowFrame.origin.y - fillFrame.origin.y) < 10
            && abs(windowFrame.size.width - fillFrame.size.width) < 10
            && abs(windowFrame.size.height - fillFrame.size.height) < 10

        if isZoomed {
            if let saved = savedFrames.removeValue(forKey: key) {
                setFrame(of: window, to: saved)
            } else {
                let w = fillFrame.width * 0.75
                let h = fillFrame.height * 0.75
                let x = fillFrame.origin.x + (fillFrame.width - w) / 2
                let y = fillFrame.origin.y + (fillFrame.height - h) / 2
                setFrame(of: window, to: CGRect(x: x, y: y, width: w, height: h))
            }
        } else {
            savedFrames[key] = windowFrame
            setFrame(of: window, to: fillFrame)
        }

        return true
    }

    // MARK: - AX helpers

    private func fullScreenButton(at pos: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var axElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(pos.x), Float(pos.y), &axElement)
        guard result == .success, let axElement else { return nil }

        var subroleValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleValue)
        guard let subrole = subroleValue as? String,
              subrole == "AXFullScreenButton" || subrole == "AXZoomButton"
        else { return nil }

        return axElement
    }

    private func windowForButton(_ button: AXUIElement) -> AXUIElement? {
        var current: AXUIElement = button
        for _ in 0..<10 {
            var parentValue: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue)
            guard let parent = parentValue else { return nil }
            let parentElement = parent as! AXUIElement
            var roleValue: AnyObject?
            AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &roleValue)
            if let role = roleValue as? String, role == kAXWindowRole {
                return parentElement
            }
            current = parentElement
        }
        return nil
    }

    private func windowKey(_ window: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? ""
        return "\(pid):\(title)"
    }

    private func getFrame(of window: AXUIElement) -> CGRect {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue)

        var position = CGPoint.zero
        var size = CGSize.zero
        if let pv = positionValue { AXValueGetValue(pv as! AXValue, .cgPoint, &position) }
        if let sv = sizeValue { AXValueGetValue(sv as! AXValue, .cgSize, &size) }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(of window: AXUIElement, to frame: CGRect) {
        var position = frame.origin
        var size = frame.size
        if let pv = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pv)
        }
        if let sv = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sv)
        }
    }

    // MARK: - Coordinate conversion

    private func screenForPoint(_ point: CGPoint) -> NSScreen {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPoint = NSPoint(x: point.x, y: primaryHeight - point.y)
        return NSScreen.screens.first(where: { $0.frame.contains(nsPoint) })
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func visibleFrameInAXCoords(screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let vf = screen.visibleFrame
        return CGRect(x: vf.origin.x, y: primaryHeight - vf.origin.y - vf.height,
                      width: vf.width, height: vf.height)
    }
}
