import Cocoa

class FinderCutHandler {
    private var cutPending = false

    private static let keyC: Int64 = 0x08
    private static let keyV: Int64 = 0x09
    private static let keyX: Int64 = 0x07

    /// Returns true if the event was consumed.
    func handleKeyDown(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard flags.contains(.maskControl),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              !flags.contains(.maskCommand),
              KeyboardUtils.isFinderApp(),
              !KeyboardUtils.isFocusedOnTextField()
        else {
            return false
        }

        // Ctrl+X: copy to clipboard and mark for move
        if keyCode == Self.keyX {
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert(.maskCommand)
            KeyboardUtils.postKey(Self.keyC, flags: newFlags)
            cutPending = true
            return true
        }

        // Ctrl+V after cut: move instead of duplicate
        if keyCode == Self.keyV && cutPending {
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert([.maskCommand, .maskAlternate])
            KeyboardUtils.postKey(Self.keyV, flags: newFlags)
            cutPending = false
            return true
        }

        // Ctrl+C cancels pending cut
        if keyCode == Self.keyC {
            cutPending = false
        }

        return false
    }
}
