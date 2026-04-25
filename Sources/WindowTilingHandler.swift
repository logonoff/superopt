import Cocoa

@MainActor
class WindowTilingHandler {
    func handleKeyDown(event: CGEvent) -> Bool {
        let flags = event.flags
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              !flags.contains(.maskShift)
        else { return false }

        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = app.processIdentifier
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case 0x7B: return KeyboardUtils.pressTilingMenuItem(pid: pid, virtualKey: 0x7B)
        case 0x7C: return KeyboardUtils.pressTilingMenuItem(pid: pid, virtualKey: 0x7C)
        case 0x7E: return KeyboardUtils.pressTilingMenuItem(pid: pid, char: "F")
        case 0x7D: return KeyboardUtils.pressTilingMenuItem(pid: pid, char: "R")
        default: return false
        }
    }
}
