import Cocoa

/// Linux/Windows-style click-through focus: one click on an inactive window both
/// brings it forward and reaches whatever is under the pointer, instead of being
/// swallowed as a bare activation click.
///
/// macOS decides this per view, through `NSView.acceptsFirstMouse(for:)`, so only
/// the app owning the window can opt in — there is no system setting and no way
/// to flip it from outside. What is possible from outside is to withhold the
/// press, focus the window the press landed on, and replay the press once that
/// focus has taken effect. This is focus-on-click, not focus-follows-mouse:
/// hovering a window still does nothing.
@MainActor
class ClickThroughFocusHandler {
    /// A press that was withheld while its target window is being focused.
    private struct PendingClick {
        let location: CGPoint
        let clickState: Int64
        let flags: CGEventFlags
        /// Where the release arrived, if it beat the replay — the replay sends a
        /// release of its own, and the pointer may have moved since the press.
        var releasedAt: CGPoint?
    }

    private struct TargetWindow {
        let pid: pid_t
        let windowID: UInt32
        let frame: CGRect
    }

    /// Presses this far below a window's top edge are left alone. macOS already
    /// raises an inactive window when its title bar is clicked, and withholding
    /// the press would break dragging the window by it.
    private static let titleBarBand: CGFloat = 28
    /// A window can be resized from just outside its frame, so a press landing
    /// in that band belongs to the window whose edge it is, not to whatever
    /// shows through behind it. Presses there are left alone.
    ///
    /// The band's real width is not observable from another process: window
    /// frame dragging is run by the window server, which ignores posted
    /// events, so a synthesized drag never resizes anything and the resize
    /// cursor never reaches `NSCursor.currentSystem`. This value is therefore
    /// chosen rather than measured, and deliberately a little wide — it also
    /// has to cover the corner grab areas, which reach further than the edges.
    /// The two ways of being wrong are not equally bad: too narrow hijacks a
    /// resize the user has already committed to, while too wide only costs
    /// click-through in a thin band around other windows' edges, where the
    /// press falls back to stock macOS behaviour.
    private static let resizeBand: CGFloat = 8
    /// How long to wait for the target window to take focus before giving up.
    private static let focusTimeout: TimeInterval = 0.25

    /// What to do with the release of a press that is no longer withheld. The window
    /// should see a matched press and release or neither, never one without the other.
    private enum AfterPress {
        /// The press was replayed and no release has followed it, so the window still
        /// has the button down. The release has to be sent on behind it.
        case replayed(PendingClick)
        /// The press was dropped because focus never landed. Its release is not the
        /// window's to see either.
        case dropped
    }

    private var pending: PendingClick?
    private var afterPress: AfterPress?
    private var pollTimer: Timer?

    /// Returns true if the event was consumed.
    func handleMouseDown(event: CGEvent) -> Bool {
        // Our own replayed press must reach the window, not be withheld again.
        guard !KeyboardUtils.isSynthetic(event) else { return false }
        if pending != nil {
            // A second press while the first is still withheld: the target has
            // not come forward yet, so letting this one through raw would
            // deliver it to the still-inactive window — swallowed as a bare
            // activation, exactly what this handler exists to fix. The first
            // press is dropped here and the new one evaluated below. Its
            // release needs no matching: on a single pointing device a second
            // press cannot precede the first's release through a working tap,
            // so an unreleased pending here means the release was missed
            // while the tap could not see it — and it has already reached the
            // window on its own. Eating the next release instead would tear
            // the new press's pair.
            reset()
        } else {
            // A new press means the last one is over, whatever became of its release.
            afterPress = nil
        }
        guard let target = frontWindow(at: event.location), needsFocus(target) else { return false }
        guard event.location.y - target.frame.minY > Self.titleBarBand else { return false }

        pending = PendingClick(
            location: event.location,
            clickState: event.getIntegerValueField(.mouseEventClickState),
            flags: event.flags
        )
        DisplayRefreshRate.startTracking()
        KeyboardUtils.raiseWindow(pid: target.pid, windowID: target.windowID)
        NSRunningApplication(processIdentifier: target.pid)?.activate()
        startPolling(target)
        return true
    }

    /// Returns true if the event was consumed.
    func handleMouseUp(event: CGEvent) -> Bool {
        guard !KeyboardUtils.isSynthetic(event) else { return false }
        if pending != nil {
            // The press is still withheld, so the release has to be too: on its own it
            // would reach the target as a mouse up with no matching mouse down.
            pending?.releasedAt = event.location
            return true
        }
        // This release belongs to a press that is no longer withheld.
        switch afterPress {
        case .replayed(let click):
            // Letting it through as it stands would race the replay: the system holds
            // input while the target app activates, so the release can arrive after
            // the press was posted but before the window has it, leaving the window
            // with the button down for good. Sending it again puts it behind the
            // press in the queue.
            afterPress = nil
            post(.leftMouseUp, click, at: event.location)
            return true
        case .dropped:
            afterPress = nil
            return true
        case nil:
            return false
        }
    }

    /// A real left press that this handler may not see (the feature is off,
    /// or the press is otherwise routed around it). Any release obligation
    /// left over from a previous press is stale — on a single pointing
    /// device a new press cannot precede that release, so it has either
    /// been consumed already or never reached the tap — and consuming THIS
    /// press's release for it would leave the window with the button down.
    func noteExternalPress() {
        afterPress = nil
    }

    /// Whether a press is withheld or its replay is still waiting for a
    /// release — the states in which `handleMouseUp` must run even while the
    /// active app is excluded. Clicking into an excluded app suspends
    /// SuperOpt from the handler's own activation, and without this the
    /// release is never recorded (or consumed after the replay), leaving the
    /// window with the button down.
    var hasPendingPress: Bool { pending != nil || afterPress != nil }

    /// Drops any withheld press, e.g. when the feature is switched off. Runs just
    /// before a replay, which then records its own release to wait for.
    func reset() {
        pollTimer?.invalidate()
        pollTimer = nil
        pending = nil
        afterPress = nil
    }

    /// Drops a withheld press whose release may still be coming, e.g. when
    /// the feature is switched off mid-hold: the window never saw the press,
    /// so its release must not reach it unmatched either. An outstanding
    /// `.dropped` obligation survives the call — `defaultsChanged` fires for
    /// every preference write, and a second one while the button is still
    /// held must not release the first one's hold on the upcoming release.
    func dropWithheldPress() {
        let unreleased = pending != nil && pending?.releasedAt == nil
        var alreadyDropped = false
        if case .dropped = afterPress { alreadyDropped = true }
        reset()
        if unreleased || alreadyDropped { afterPress = .dropped }
    }

    // MARK: - Hit testing

    /// The frontmost normal window containing `point`, or nil when the press
    /// should be left to macOS.
    private func frontWindow(at point: CGPoint) -> TargetWindow? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        // Mission Control's shield covers every window but leaves them all in the
        // list, so without this the press would target whatever sits underneath.
        if KeyboardUtils.isMissionControlActive(list) { return nil }
        return frontWindow(at: point, in: list)
    }

    private func frontWindow(at point: CGPoint, in list: [[String: Any]]) -> TargetWindow? {
        // The list runs front to back, so the first window containing the point is
        // the one the press lands on. Bail out if that window is above the normal
        // window layer — the menu bar, the Dock, open menus and notifications all
        // take a click while inactive already — or below it, which is the desktop.
        for info in list {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds)
            else { continue }
            let layer = info[kCGWindowLayer as String] as? Int
            // The cursor window follows the pointer and always contains the
            // point — it is the pointer, not a click target. Skipping it the
            // way MiddleClickPasteWindow.frontWindow does keeps a click at a
            // position the pointer was recently warped to click-through-able.
            if layer == Int(CGWindowLevelForKey(.cursorWindow)) { continue }
            guard frame.contains(point) else {
                // Not in this window, but near enough outside it to be grabbing
                // its edge. Front to back means any window reaching this point
                // is in front of whatever the press would otherwise land on, so
                // its resize band wins and the press is macOS's to interpret.
                if layer == 0, frame.insetBy(dx: -Self.resizeBand, dy: -Self.resizeBand).contains(point) {
                    return nil
                }
                continue
            }
            guard layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? UInt32,
                  pid != ProcessInfo.processInfo.processIdentifier
            else { return nil }
            return TargetWindow(pid: pid, windowID: windowID, frame: frame)
        }
        return nil
    }

    private func needsFocus(_ target: TargetWindow) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.processIdentifier != target.pid { return true }
        // Same app, different window — macOS swallows that press too. This is the
        // case of two browser windows, where pausing a video in the back one takes
        // a click to focus it and a second click to hit the button.
        guard let focused = KeyboardUtils.focusedWindowID(pid: target.pid) else { return false }
        return focused != target.windowID
    }

    // MARK: - Replay

    /// Polls at the display refresh rate: the window being in front is something
    /// the user is about to see, so there is no point checking for it more often
    /// than the screen can draw it, and no point checking less often either —
    /// every frame the replay is late is a frame of lag on their click.
    private func startPolling(_ target: TargetWindow) {
        pollTimer?.invalidate()
        let deadline = Date().addingTimeInterval(Self.focusTimeout)
        let timer = Timer(timeInterval: DisplayRefreshRate.frameInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, let pending = self.pending else { timer.invalidate(); return }
                // Replaying a press that would now land on a different window would
                // click the wrong thing, so the target has to still be in front.
                let onTop = self.frontWindow(at: pending.location)?.windowID == target.windowID
                let active = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
                guard (onTop && active) || Date() >= deadline else { return }
                self.reset()
                if onTop {
                    self.replay(pending)
                } else if pending.releasedAt == nil {
                    // The press is being dropped. Its release is still to come, and
                    // on its own it would reach the window unmatched.
                    self.afterPress = .dropped
                }
            }
        }
        // Common modes so the replay still happens while a menu or a resize is
        // tracking the run loop.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func replay(_ click: PendingClick) {
        post(.leftMouseDown, click, at: click.location)
        // The pointer can travel while the press is withheld — a click and drag
        // started on an inactive window. Releasing where the press began would
        // collapse that into a click on the spot the drag started from.
        if let releasedAt = click.releasedAt {
            post(.leftMouseUp, click, at: releasedAt)
        } else {
            // Still held, or released into the gap this replay just raced through.
            afterPress = .replayed(click)
        }
    }

    private func post(_ type: CGEventType, _ click: PendingClick, at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type, mouseCursorPosition: location, mouseButton: .left
        ) else { return }
        event.flags = click.flags
        event.setIntegerValueField(.mouseEventClickState, value: click.clickState)
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardUtils.syntheticTag)
        event.post(tap: .cgSessionEventTap)
    }
}
