import Cocoa

class MiddleClickPasteHandler {
    private static let keyV: CGKeyCode = 0x09

    /// Returns true if the event was consumed.
    func handleMouseDown(event: CGEvent) -> Bool {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        guard buttonNumber == 2 else { return false }

        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: Self.keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: Self.keyV, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
