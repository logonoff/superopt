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
    /// Whether the cut's own copy was seen landing on the pasteboard.
    private var cutConfirmed = false
    private var confirmTimer: Timer?
    /// When the cut was taken, for the paste-time promptness check.
    private var cutAt: TimeInterval = 0
    /// How long after a cut its own copy is expected to land by. Finder posts
    /// the pasteboard write within tens of milliseconds, while a copy the
    /// user makes after an empty-selection cut is a selection and a keystroke
    /// away — two actions no one completes inside the window — so a count
    /// that moves only later cannot be attributed to the cut.
    private static let confirmWindow: TimeInterval = 0.2
    private var mode: FinderCutMode = .off

    private static let keyC: Int64 = 0x08
    private static let keyV: Int64 = 0x09
    private static let keyX: Int64 = 0x07

    init() { reloadSettings() }

    func reloadSettings() {
        let newMode = FinderCutMode(
            rawValue: UserDefaults.standard.integer(forKey: "finderCutMode")
        ) ?? .off
        // A cut taken under the old setting must not complete under the new
        // one. `didChangeNotification` fires for every preference write —
        // pane switches, unrelated toggles, macOS's own housekeeping keys —
        // so the clear has to be limited to actual mode changes or an
        // unrelated write would drop a pending cut.
        if newMode != mode { clearCut() }
        mode = newMode
    }

    /// Returns true if the event was consumed.
    func handleKeyDown(event: CGEvent) -> Bool {
        guard mode != .off,
              KeyboardUtils.isFinderApp(),
              !KeyboardUtils.isFocusedOnTextField()
        else { return false }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        // Held keys autorepeat, and re-running the cut on every repeat would
        // re-post Finder's ⌘C and restart the confirmation window for as
        // long as the key is held.
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        switch mode {
        case .control:
            return handleControl(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .command:
            return handleCommand(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        case .off:
            return false
        }
    }

    private func handleControl(keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        guard flags.contains(.maskControl),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              !flags.contains(.maskCommand)
        else { return false }

        if keyCode == Self.keyX {
            // The first press already cut; a held key's repeats are consumed
            // rather than re-cutting.
            guard !isRepeat else { return true }
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert(.maskCommand)
            beginCut { KeyboardUtils.postKey(Self.keyC, flags: newFlags) }
            return true
        }

        if keyCode == Self.keyV && cutPending {
            // A stale cut falls back to an ordinary paste: the pasteboard
            // holds something the user did not cut here, and moving it would
            // take files out of a folder they never cut them from.
            let move = cutIsOnPasteboard()
            var newFlags = flags
            newFlags.remove(.maskControl)
            newFlags.insert(move ? [.maskCommand, .maskAlternate] : .maskCommand)
            KeyboardUtils.postKey(Self.keyV, flags: newFlags)
            clearCut()
            return true
        }

        if keyCode == Self.keyC { clearCut() }
        return false
    }

    private func handleCommand(keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        guard flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift),
              !flags.contains(.maskControl)
        else { return false }

        if keyCode == Self.keyX {
            // The first press already cut; a held key's repeats are consumed
            // rather than re-cutting.
            guard !isRepeat else { return true }
            beginCut { KeyboardUtils.postKey(Self.keyC, flags: flags) }
            return true
        }

        if keyCode == Self.keyV && cutPending {
            // A stale cut falls back to an ordinary paste rather than moving
            // something the user did not cut here.
            let move = cutIsOnPasteboard()
            var newFlags = flags
            if move { newFlags.insert(.maskAlternate) }
            KeyboardUtils.postKey(Self.keyV, flags: newFlags)
            clearCut()
            return true
        }

        if keyCode == Self.keyC { clearCut() }
        return false
    }

    /// Ends the pending cut, if any, and stops watching for its copy.
    private func clearCut() {
        cutPending = false
        confirmTimer?.invalidate()
        confirmTimer = nil
    }

    /// Marks files as cut and runs `copy`, which hands the files to Finder's own copy.
    private func beginCut(_ copy: () -> Void) {
        cutChangeCount = NSPasteboard.general.changeCount
        cutConfirmed = false
        cutAt = ProcessInfo.processInfo.systemUptime
        copy()
        cutPending = true
        watchForCutCopy()
    }

    /// Latches whether the cut's own copy lands on the pasteboard. The count
    /// moving is only proof when it moves promptly: a copy the user makes
    /// after an empty-selection cut — ⌘C, the Edit menu, the context menu,
    /// another app — lands as exactly +1 too, and reading it as the cut would
    /// move files the user only copied. Finder's own copy lands within tens
    /// of milliseconds, so a count that has not moved by the end of the
    /// window cannot be attributed to the cut.
    private func watchForCutCopy() {
        confirmTimer?.invalidate()
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.cutPending else { timer.invalidate(); return }
                // Bounded by the window at observation time, not just by the
                // timer's schedule: a tick delayed past the window by a busy
                // run loop must not latch a copy that landed after it.
                if NSPasteboard.general.changeCount != self.cutChangeCount,
                   ProcessInfo.processInfo.systemUptime - started <= Self.confirmWindow {
                    self.cutConfirmed = true
                }
                if self.cutConfirmed
                    || ProcessInfo.processInfo.systemUptime - started >= Self.confirmWindow {
                    timer.invalidate()
                    if self.confirmTimer === timer { self.confirmTimer = nil }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        confirmTimer = timer
    }

    /// Whether the files marked as cut are still the ones on the pasteboard.
    ///
    /// Finder's copy bumps the change count exactly once — measured for a single file
    /// and for a multiple selection alike — so only that result means the cut's own
    /// copy landed. An unmoved count means it never did: an empty selection, or a
    /// volume too slow to have processed the ⌘C by the time ⌘V was pressed. Either
    /// way the pasteboard still holds whatever was copied before the cut, and moving
    /// that would take files the user never cut out of the folder they are in, so
    /// the paste falls back to copying like any other paste. Anything past +1 is a
    /// copy made somewhere this handler cannot see: the Edit menu, a context menu,
    /// another app — pasting then has to copy too, because moving files the user
    /// only copied takes them out of the folder they are looking at. The +1 itself
    /// is only attribution when the copy landed within the confirm window — seen
    /// by the watch, or still inside the window at paste time — and the pasteboard
    /// holds file URLs; a later +1 is a copy the user made, and a prompt +1 of
    /// anything else is a background writer (Universal Clipboard, a clipboard
    /// manager) that Finder could not move anyway. A background writer that
    /// itself lands file URLs promptly remains indistinguishable from the cut's
    /// own copy — an accepted residual: no API names a pasteboard change's author.
    private func cutIsOnPasteboard() -> Bool {
        guard cutPending else { return false }
        let count = NSPasteboard.general.changeCount
        // A paste fast enough to beat the watch's first tick still counts:
        // the copy has landed and the window is still open, and nothing the
        // user copies can get there — selecting a file and copying it is two
        // actions, neither of which happens inside the window.
        let landedPromptly = cutConfirmed
            || (count != cutChangeCount
                && ProcessInfo.processInfo.systemUptime - cutAt <= Self.confirmWindow)
        let holdsFiles = NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        guard landedPromptly, holdsFiles, count == cutChangeCount + 1 else {
            clearCut()
            return false
        }
        return true
    }
}
