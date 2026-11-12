import Cocoa

/// The system's own "Move left/right a space" shortcut, as the user has it configured.
///
/// Spaces are switched by posting this rather than by telling the window server to
/// change space directly. `SLSManagedDisplaySetCurrentSpace` does move the space, but
/// it only updates the bookkeeping: the menu bar is left drawing the old space's app
/// over the new one's, and nothing short of a real space switch puts that right.
/// Posting the shortcut is the real switch, so macOS does all of it — and it acts on
/// the display under the pointer, which is the display whose Apple menu was scrolled.
enum SpaceShortcut {
    enum Direction {
        case left, right

        /// System Settings stores the two shortcuts under these fixed IDs.
        var hotkeyID: String { self == .left ? "79" : "81" }
        /// What macOS ships with, used when the user has never touched the setting and
        /// the preference holds no entry at all.
        var defaultKeyCode: Int64 { self == .left ? 0x7B : 0x7C }
    }

    struct Binding {
        let keyCode: Int64
        let flags: CGEventFlags
    }

    /// Posts the shortcut. False means there is nothing to post because the user turned
    /// the shortcut off, in which case macOS would not switch spaces by keyboard either.
    @discardableResult
    static func post(_ direction: Direction) -> Bool {
        guard let binding = binding(for: direction) else { return false }
        KeyboardUtils.postKey(binding.keyCode, flags: binding.flags)
        return true
    }

    static func binding(for direction: Direction) -> Binding? {
        guard let hotkeys = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any], let entry = hotkeys[direction.hotkeyID] as? [String: Any] else {
            // No entry means the shortcut has never been changed, so it is the default:
            // Control and the arrow key, with the function bit arrows always carry.
            return Binding(keyCode: direction.defaultKeyCode,
                           flags: [.maskControl, .maskSecondaryFn])
        }

        guard entry["enabled"] as? Bool ?? false,
              let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count >= 3
        else { return nil }

        return Binding(keyCode: Int64(parameters[1]), flags: flags(fromCarbon: parameters[2]))
    }

    /// The stored mask is the Carbon-era one `NSEvent` also uses, not `CGEventFlags`.
    private static func flags(fromCarbon mask: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if mask & 0x20000 != 0 { flags.insert(.maskShift) }
        if mask & 0x40000 != 0 { flags.insert(.maskControl) }
        if mask & 0x80000 != 0 { flags.insert(.maskAlternate) }
        if mask & 0x100000 != 0 { flags.insert(.maskCommand) }
        if mask & 0x800000 != 0 { flags.insert(.maskSecondaryFn) }
        return flags
    }
}
