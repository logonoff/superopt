import Cocoa
import Carbon.HIToolbox

/// Layout-aware key translation.
///
/// Key codes are physical positions, so a remap that *changes* keys — ⌃Y →
/// ⇧⌘Z, Alt+F4 → ⌘W — lands on the wrong letter under QWERTZ or AZERTY, where
/// the letters live at different positions: on German QWERTZ, ⌃Z emits the
/// code the handler thinks is Y, and both undo and redo go dead. These
/// helpers resolve a character to the key code that produces it under the
/// current layout, and back, so a remap can be spelled in characters and
/// still fire positionally. Same-key modifier swaps (⌃C → ⌘C) need none of
/// this — position in, position out.
enum KeyboardLayout {
    /// Only ever touched from the CGEvent tap callback and the input-source
    /// observer — both run on the main run loop — so no synchronisation is
    /// needed, matching the other event-tap helpers.
    nonisolated(unsafe) private static var charByKeyCode: [Int64: String] = [:]
    nonisolated(unsafe) private static var keyCodeByChar: [String: Int64] = [:]
    nonisolated(unsafe) private static var cacheKey: String?
    nonisolated(unsafe) private static var observerInstalled = false

    /// The character the key at `keyCode` types unshifted, lowercased — under
    /// the current layout, or under US ANSI when no layout can be read.
    static func character(forKeyCode keyCode: Int64) -> String? {
        rebuildIfNeeded()
        return charByKeyCode[keyCode] ?? usLetters[keyCode]
    }

    /// A key code that types `character` under the current layout — the first
    /// unshifted position that produces it — or its US ANSI position when no
    /// layout can be read. Nil when no key types it at all.
    static func keyCode(forCharacter character: String) -> Int64? {
        rebuildIfNeeded()
        if let code = keyCodeByChar[character] { return code }
        return usLetters.first(where: { $0.value == character })?.key
    }

    /// The character at `keyCode` on a US ANSI keyboard, the fixed reference
    /// the shortcut tables are written against.
    static func usCharacter(forKeyCode keyCode: Int64) -> String? {
        usLetters[keyCode]
    }

    /// US ANSI letter positions. `ctrlToCmdMap` and friends are keyed by
    /// these; the character-keyed tables are derived from them so the two
    /// representations can never drift apart.
    private static let usLetters: [Int64: String] = [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f",
        0x04: "h", 0x05: "g", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l",
        0x2E: "m", 0x2D: "n", 0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r",
        0x01: "s", 0x11: "t", 0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x",
        0x10: "y", 0x06: "z"
    ]

    /// Whether `char` is a single ASCII lowercase letter — the only keys
    /// whose positions move between layouts worth matching by character.
    static func isLetter(_ char: String) -> Bool {
        guard char.count == 1, let scalar = char.unicodeScalars.first else {
            return false
        }
        return (97...122).contains(scalar.value)
    }

    // MARK: - Cache

    /// Rebuilds the translation tables when the selected input source has
    /// changed. The rebuild walks 128 key codes through UCKeyTranslate —
    /// microseconds — and happens once per layout change, not per event.
    private static func rebuildIfNeeded() {
        installObserverIfNeeded()
        let key = currentSourceID()
        if key == cacheKey { return }
        guard let data = currentKeyboardLayoutData(),
              let bytes = CFDataGetBytePtr(data) else {
            // cacheKey is left untouched so a failed read is retried on the
            // next query rather than pinning the US fallback to this source.
            return
        }
        cacheKey = key
        charByKeyCode.removeAll()
        keyCodeByChar.removeAll()
        // The layout data is a CFData the input source owns; UCKeyTranslate
        // needs it as UCKeyboardLayout, rebound only for the duration of the
        // walk below.
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for keyCode in 0..<128 {
                var deadKeyState: UInt32 = 0
                var chars = [UniChar](repeating: 0, count: 4)
                var length = 0
                let error = UCKeyTranslate(
                    layout,
                    UInt16(keyCode),
                    UInt16(kUCKeyActionDisplay),
                    0, // no modifiers: the unshifted character
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )
                guard error == noErr, length > 0 else { continue }
                let string = String(utf16CodeUnits: chars, count: length).lowercased()
                // Scalar count, not grapheme count: a decomposed output
                // (base letter + combining mark) is one grapheme but would
                // never match the pure-ASCII shortcut tables.
                guard string.unicodeScalars.count == 1 else { continue }
                charByKeyCode[Int64(keyCode)] = string
                if keyCodeByChar[string] == nil {
                    keyCodeByChar[string] = Int64(keyCode)
                }
            }
        }
    }

    /// The keyboard layout data of the selected input source. Public API
    /// stops at "which input source is selected"; translating key codes
    /// requires the layout data itself, which only TIS hands out. The
    /// property follows the Get rule — the raw pointer is storage the input
    /// source owns, and the source is released when this function returns —
    /// so it is retained explicitly before being handed to ARC, which
    /// balances the release when the caller is done with it.
    private static func currentKeyboardLayoutData() -> CFData? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?
            .takeRetainedValue() else { return nil }
        guard let layoutRef = TISGetInputSourceProperty(
            source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(layoutRef).retain().takeRetainedValue()
    }

    private static func currentSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?
            .takeRetainedValue() else { return nil }
        guard let idRef = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(idRef).takeUnretainedValue() as String
    }

    /// Invalidates the cache the moment the user changes input source, rather
    /// than at the next query.
    private static func installObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.KeyboardPreferences.SelectedInputSourceChanged"),
            object: nil, queue: .main
        ) { _ in
            cacheKey = nil
        }
    }
}
