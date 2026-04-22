import Cocoa

/* Note: terminal apps are skipped by this class since CGEvents can't inject into
   a PTY. For Terminal.app, configure Home/End manually.

   Run in the terminal, then restart Terminal.app:

# Terminal.app: map Home/End to escape sequences
PROFILE=$(defaults read com.apple.Terminal "Default Window Settings")
/usr/libexec/PlistBuddy \
  -c "Add ':Window Settings:${PROFILE}:keyMapBoundKeys:F729' string '\033[H'" \
  -c "Add ':Window Settings:${PROFILE}:keyMapBoundKeys:F72B' string '\033[F'" \
  ~/Library/Preferences/com.apple.Terminal.plist 2>/dev/null || \
/usr/libexec/PlistBuddy \
  -c "Set ':Window Settings:${PROFILE}:keyMapBoundKeys:F729' '\033[H'" \
  -c "Set ':Window Settings:${PROFILE}:keyMapBoundKeys:F72B' '\033[F'" \
  ~/Library/Preferences/com.apple.Terminal.plist

# zsh: bind the escape sequences to cursor movement
grep -q 'beginning-of-line' ~/.zshrc 2>/dev/null || \
  printf '\n# Home/End\nbindkey "\\e[H" beginning-of-line\nbindkey "\\e[F" end-of-line\n' \
  >> ~/.zshrc && source ~/.zshrc
*/

class HomeEndHandler {
    private static let keyHome: Int64 = 0x73
    private static let keyEnd: Int64 = 0x77
    private static let keyLeft: Int64 = 0x7B
    private static let keyRight: Int64 = 0x7C
    private static let keyUp: Int64 = 0x7E
    private static let keyDown: Int64 = 0x7D

    func handleKeyDown(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard keyCode == HomeEndHandler.keyHome || keyCode == HomeEndHandler.keyEnd else {
            return false
        }

        if KeyboardUtils.isTerminalApp() { return false }
        guard KeyboardUtils.isFocusedOnTextField() else { return false }

        let isHome = keyCode == HomeEndHandler.keyHome
        let hasCtrl = event.flags.contains(.maskControl)
        // Ctrl+Home/End → Cmd+Up/Down (document start/end)
        // Home/End → Cmd+Left/Right (line start/end)
        let arrowKey: Int64
        if hasCtrl {
            arrowKey = isHome ? HomeEndHandler.keyUp : HomeEndHandler.keyDown
        } else {
            arrowKey = isHome ? HomeEndHandler.keyLeft : HomeEndHandler.keyRight
        }
        var newFlags = event.flags
        newFlags.remove(.maskControl)
        newFlags.insert(.maskCommand)
        KeyboardUtils.rewriteEvent(event, keyCode: arrowKey, flags: newFlags)
        return true
    }
}
