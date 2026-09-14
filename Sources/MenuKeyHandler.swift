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

        // event.location is the current pointer position, so the caret click can put
        // it back afterwards. The other two paths never move it.
        if let caret = caretScreenPoint(),
           postRightClick(at: caret, restoringCursorTo: event.location) { return true }
        if showTextFieldContextMenu() { return true }
        return postRightClick(at: event.location, restoringCursorTo: nil)
    }

    private func focusedElement() -> AXUIElement? {
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            KeyboardUtils.systemWide, kAXFocusedUIElementAttribute as CFString,
            &focusedRef) == .success
        else { return nil }
        return focusedRef.flatMap(KeyboardUtils.toAXElement)
    }

    /// Screen position of the insertion point in the focused text field.
    ///
    /// `kAXShowMenuAction` opens the menu in the middle of the element rather than at
    /// the caret, which is very visible in a long field like Firefox's address bar.
    /// Asking the element where the caret actually is lets the menu open there.
    ///
    /// Returns nil unless the selection is empty: for a non-empty selection the
    /// element reports the selection's bounding box rather than a caret, and
    /// right-clicking inside it risks collapsing the selection and dropping Cut and
    /// Copy from the menu. Those fall back to `kAXShowMenuAction`, which leaves the
    /// selection alone.
    private func caretScreenPoint() -> CGPoint? {
        guard let element = focusedElement() else { return nil }

        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef.flatMap(KeyboardUtils.toAXValue)
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range), range.length == 0
        else { return nil }

        // Not every app implements this parameterized attribute — Electron apps such
        // as VS Code expose no focused element at all — so fall back when it fails.
        var boundsRef: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue, &boundsRef) == .success,
              let boundsValue = boundsRef.flatMap(KeyboardUtils.toAXValue)
        else { return nil }

        var caret = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &caret), caret.height > 0
        else { return nil }

        // AX reports screen coordinates with a top-left origin, the same space CGEvent
        // mouse locations use, so the rect needs no conversion. Aim at the middle of
        // the caret's line so the click lands in the text rather than on the field edge.
        let point = CGPoint(x: caret.minX, y: caret.midY)

        // Trust the caret only when it really sits in the field. Spotlight reports one
        // a full caret-height above its search field (field y 263..321, caret y
        // 233..264), so clicking there misses the field entirely. Apps that get this
        // wrong fall back to kAXShowMenuAction, which positions the menu itself.
        guard let field = elementFrame(element) else { return nil }
        let overlap = caret.intersection(field)
        guard !overlap.isNull, overlap.height >= caret.height / 2, field.contains(point)
        else { return nil }
        return point
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef.flatMap(KeyboardUtils.toAXValue),
              let sizeValue = sizeRef.flatMap(KeyboardUtils.toAXValue)
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Clicking at the caret moves the pointer there, so put it back to make the key
    /// feel like a keyboard shortcut rather than a mouse gesture. The menu has to be
    /// up first: apps that position it from `NSEvent.mouseLocation` instead of the
    /// event's own location would otherwise open it wherever the pointer ended up.
    private static let cursorRestoreDelay: TimeInterval = 0.05

    private func postRightClick(at point: CGPoint, restoringCursorTo origin: CGPoint?) -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let mouseDown = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown,
                                      mouseCursorPosition: point, mouseButton: .right),
              let mouseUp = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp,
                                    mouseCursorPosition: point, mouseButton: .right)
        else { return false }
        mouseDown.post(tap: .cgSessionEventTap)
        mouseUp.post(tap: .cgSessionEventTap)

        guard let origin, origin != point else { return true }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cursorRestoreDelay) {
            // Warp rather than posting a mouse-moved event: the open menu would treat
            // a move as the pointer travelling back across it and change its highlight.
            CGWarpMouseCursorPosition(origin)
        }
        return true
    }

    private func showTextFieldContextMenu() -> Bool {
        guard let element = focusedElement() else { return false }

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
