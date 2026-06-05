import Cocoa

enum FinderCutMode: Int {
    case off = 0
    case command = 1   // ⌘X / ⌘V
    case control = 2   // ⌃X / ⌃V
}

@MainActor
class FinderCutHandler {
    private var cutPending = false
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
            KeyboardUtils.postKey(Self.keyC, flags: newFlags)
            cutPending = true
            return true
        }

        if keyCode == Self.keyV && cutPending {
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
            KeyboardUtils.postKey(Self.keyC, flags: flags)
            cutPending = true
            return true
        }

        if keyCode == Self.keyV && cutPending {
            var newFlags = flags
            newFlags.insert(.maskAlternate)
            KeyboardUtils.postKey(Self.keyV, flags: newFlags)
            cutPending = false
            return true
        }

        if keyCode == Self.keyC { cutPending = false }
        return false
    }
}
