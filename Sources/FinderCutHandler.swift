import Cocoa

enum FinderCutMode: Int {
    case off = 0
    case command = 1   // ⌘X / ⌘V
    case control = 2   // ⌃X / ⌃V
}

@MainActor
class FinderCutHandler {
    private var cutPending = false
    /// Pasteboard change count as it was when the cut was taken.
    private var cutChangeCount = 0
    private var mode: FinderCutMode = .off

    private static let keyC: Int64 = 0x08
    private static let keyV: Int64 = 0x09
    private static let keyX: Int64 = 0x07

    init() { reloadSettings() }

    func reloadSettings() {
        mode = FinderCutMode(
            rawValue: UserDefaults.standard.integer(forKey: "finderCutMode")
        ) ?? .off
    }

    /// Returns true if the event was consumed.
    func handleKeyDown(event: CGEvent) -> Bool {
        guard mode != .off,
              KeyboardUtils.isFinderApp(),
              !KeyboardUtils.isFocusedOnTextField()
        else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        switch mode {
        case .control:
            return handleControl(keyCode: keyCode, flags: flags)
        case .command:
            return handleCommand(keyCode: keyCode, flags: flags)
        case .off:
            return false
        }
    }

    private func handleControl(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskControl),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              !flags.contains(.maskCommand)
        else { return false }

        if keyCode == Self.keyX {
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert(.maskCommand)
            beginCut { KeyboardUtils.postKey(Self.keyC, flags: newFlags) }
            return true
        }

        if keyCode == Self.keyV && cutIsOnPasteboard() {
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert([.maskCommand, .maskAlternate])
            KeyboardUtils.postKey(Self.keyV, flags: newFlags)
            cutPending = false
            return true
        }

        if keyCode == Self.keyC { cutPending = false }
        return false
    }

    private func handleCommand(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              !flags.contains(.maskControl)
        else { return false }

        if keyCode == Self.keyX {
            beginCut { KeyboardUtils.postKey(Self.keyC, flags: flags) }
            return true
        }

        if keyCode == Self.keyV && cutIsOnPasteboard() {
            var newFlags = flags
            newFlags.insert(.maskAlternate)
            KeyboardUtils.postKey(Self.keyV, flags: newFlags)
            cutPending = false
            return true
        }

        if keyCode == Self.keyC { cutPending = false }
        return false
    }

    /// Marks files as cut and runs `copy`, which hands the files to Finder's own copy.
    private func beginCut(_ copy: () -> Void) {
        cutChangeCount = NSPasteboard.general.changeCount
        copy()
        cutPending = true
    }

    /// Whether the files marked as cut are still the ones on the pasteboard.
    ///
    /// Finder's copy bumps the change count exactly once — measured for a single file
    /// and for a multiple selection alike — so anything past that is a copy made
    /// somewhere this handler cannot see: the Edit menu, a context menu, another app.
    /// Pasting then has to copy like any other paste, because moving files the user
    /// only copied takes them out of the folder they are looking at.
    private func cutIsOnPasteboard() -> Bool {
        guard cutPending else { return false }
        guard NSPasteboard.general.changeCount <= cutChangeCount + 1 else {
            cutPending = false
            return false
        }
        return true
    }
}
