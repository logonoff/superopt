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
        /// Set when the release arrives before the press has been replayed, so
        /// the replay knows to send a release of its own.
        var released = false
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
    /// How long to wait for the target window to take focus before giving up.
    private static let focusTimeout: TimeInterval = 0.25

    private var pending: PendingClick?
    private var pollTimer: Timer?

    /// Returns true if the event was consumed.
    func handleMouseDown(event: CGEvent) -> Bool {
        // Our own replayed press must reach the window, not be withheld again.
        guard !KeyboardUtils.isSynthetic(event), pending == nil else { return false }
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
        guard !KeyboardUtils.isSynthetic(event), pending != nil else { return false }
        // The press is still withheld, so the release has to be too: on its own it
        // would reach the target as a mouse up with no matching mouse down.
        pending?.released = true
        return true
    }

    /// Drops any withheld press, e.g. when the feature is switched off.
    func reset() {
        pollTimer?.invalidate()
        pollTimer = nil
        pending = nil
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
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.contains(point)
            else { continue }
            guard info[kCGWindowLayer as String] as? Int == 0,
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
        guard let focused = focusedWindowID(pid: target.pid) else { return false }
        return focused != target.windowID
    }

    private func focusedWindowID(pid: pid_t) -> UInt32? {
        guard let getWindow = KeyboardUtils.axGetWindow else { return nil }
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &ref
        ) == .success, let window = ref.flatMap(KeyboardUtils.toAXElement) else { return nil }
        var windowID: UInt32 = 0
        guard getWindow(window, &windowID) == 0 else { return nil }
        return windowID
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
                if onTop { self.replay(pending) }
            }
        }
        // Common modes so the replay still happens while a menu or a resize is
        // tracking the run loop.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func replay(_ click: PendingClick) {
        post(.leftMouseDown, click)
        if click.released { post(.leftMouseUp, click) }
    }

    private func post(_ type: CGEventType, _ click: PendingClick) {
        guard let event = CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: type, mouseCursorPosition: click.location, mouseButton: .left
        ) else { return }
        event.flags = click.flags
        event.setIntegerValueField(.mouseEventClickState, value: click.clickState)
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardUtils.syntheticTag)
        event.post(tap: .cgSessionEventTap)
    }
}
