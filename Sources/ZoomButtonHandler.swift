import Cocoa

class ZoomButtonHandler {
    private var savedFrames: [String: CGRect] = [:]
    private static let maxSavedFrames = 50

    /// Returns true if the event should be consumed.
    func handleClick(event: CGEvent) -> Bool {
        if event.flags.contains(.maskAlternate) { return false }

        let pos = event.location
        guard let button = fullScreenButton(at: pos),
              let window = windowForButton(button),
              let screen = screenForPoint(pos)
        else { return false }

        let windowFrame = getFrame(of: window)
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
                let fallbackWidth = fillFrame.width * 0.75
                let fallbackHeight = fillFrame.height * 0.75
                let fallbackX = fillFrame.origin.x + (fillFrame.width - fallbackWidth) / 2
                let fallbackY = fillFrame.origin.y + (fillFrame.height - fallbackHeight) / 2
                setFrame(of: window, to: CGRect(
                    x: fallbackX, y: fallbackY,
                    width: fallbackWidth, height: fallbackHeight))
            }
        } else {
            if savedFrames.count >= Self.maxSavedFrames { savedFrames.removeAll() }
            savedFrames[key] = windowFrame
            setFrame(of: window, to: fillFrame)
        }

        return true
    }

    // MARK: - AX helpers

    private func fullScreenButton(at pos: CGPoint) -> AXUIElement? {
        var axElement: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(KeyboardUtils.systemWide, Float(pos.x), Float(pos.y), &axElement)
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
            guard let parent = parentValue,
                  let parentElement = KeyboardUtils.toAXElement(parent)
            else { return nil }
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
        if let positionValue, let axPos = KeyboardUtils.toAXValue(positionValue) {
            AXValueGetValue(axPos, .cgPoint, &position)
        }
        if let sizeValue, let axSize = KeyboardUtils.toAXValue(sizeValue) {
            AXValueGetValue(axSize, .cgSize, &size)
        }
        return CGRect(origin: position, size: size)
    }

    private func setFrame(of window: AXUIElement, to frame: CGRect) {
        var position = frame.origin
        var size = frame.size
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: - Coordinate conversion

    private func screenForPoint(_ point: CGPoint) -> NSScreen? {
        let nsPoint = NSPoint(x: point.x, y: KeyboardUtils.primaryScreenHeight() - point.y)
        return NSScreen.screens.first(where: { $0.frame.contains(nsPoint) })
            ?? NSScreen.main
    }

    private func visibleFrameInAXCoords(screen: NSScreen) -> CGRect {
        let primaryHeight = KeyboardUtils.primaryScreenHeight()
        let visible = screen.visibleFrame
        return CGRect(x: visible.origin.x, y: primaryHeight - visible.origin.y - visible.height,
                      width: visible.width, height: visible.height)
    }
}
