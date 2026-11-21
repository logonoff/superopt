import Cocoa

/// Tracks whether Mission Control is on screen, for the features that need to know.
///
/// Normally polling starts from a trigger —
/// the app opening Mission Control itself, or the event tap seeing the Mission Control
/// key — and stops again when Mission Control goes away, or when it never showed up
/// within `graceWindow`. Opening Mission Control some other way (a trackpad swipe,
/// the Dock icon) produces no trigger, so callers that are doing work anyway and can
/// afford a window list walk use `check()` to find it that way instead. Dynamic
/// Spaces also needs to notice a swipe with no subsequent input, so it requests
/// a slow visibility check while idle. Desktop and AX queries only run once open.
@MainActor
final class MissionControlMonitor {
    private(set) var isActive = false

    /// Bumped each time Mission Control appears, so a caller can tell one appearance
    /// from the next. `isActive` alone is not enough for that: it stays true through
    /// the ~320 ms Mission Control takes to animate closed, which is long enough for
    /// a caller that just dismissed it to think a second one had opened.
    private(set) var activationID = 0

    /// Fired on every poll while Mission Control is up, carrying the window list that
    /// was just fetched so subscribers don't walk it a second time.
    var onActive: (([[String: Any]]) -> Void)?
    /// Fired once when Mission Control goes away.
    var onInactive: (() -> Void)?

    private var detectsUnsignalledOpen = false
    private var enabled = false
    private var timer: Timer?
    private var lastCheck: TimeInterval = 0
    private var graceDeadline: TimeInterval = 0

    /// Slow enough to cost nothing, fast enough that the close buttons show up
    /// promptly once Mission Control is already open and being looked at.
    private static let pollInterval: TimeInterval = 0.25
    /// Rate to look for Mission Control at between a trigger and its arrival. Polling
    /// at `pollInterval` here leaves `isActive` wrong for up to 250 ms — the whole of
    /// the opening animation — and anything relying on it silently misses that window.
    private static var searchInterval: TimeInterval { DisplayRefreshRate.frameInterval }
    /// How long to keep polling after a trigger before giving up on Mission Control.
    private static let graceWindow: TimeInterval = 2.0

    /// True while a trigger is outstanding and Mission Control has yet to be
    /// seen arriving or leaving — the key toggles, so a trigger may be a
    /// close, and while one is unresolved the poll stays at the frame rate:
    /// the first tick after a closing trigger still sees the ~320 ms close
    /// animation, and dropping to 4 Hz there would leave `isActive`
    /// stale-true for up to ~570 ms after the close.
    private var triggerOutstanding = false

    /// True while a trigger is outstanding and Mission Control has yet to appear —
    /// it is on its way in, so a caller that cares is better off looking right now
    /// than waiting for the next poll.
    var isOpening: Bool {
        !isActive && triggerOutstanding && enabled
            && ProcessInfo.processInfo.systemUptime <= graceDeadline
    }

    func start(detectUnsignalledOpen: Bool) {
        let changed = !enabled || detectsUnsignalledOpen != detectUnsignalledOpen
        enabled = true
        detectsUnsignalledOpen = detectUnsignalledOpen
        if changed && !isActive && !triggerOutstanding { idle() }
        DisplayRefreshRate.startTracking()
    }

    func stop() {
        enabled = false
        triggerOutstanding = false
        stopTimer()
        guard isActive else { return }
        isActive = false
        onInactive?()
    }

    /// Called when something that might have opened Mission Control happened. Entering
    /// or leaving Mission Control with the pointer held still generates no mouse-moved
    /// event, so without this nothing would notice either transition. The key toggles,
    /// so a trigger may close Mission Control too — accelerating detection either way
    /// matters: while active, the 4 Hz poll can leave `isActive` stale-true for up to
    /// ~570 ms after a close, during which callers would act on a Mission Control that
    /// is already gone.
    func noteTrigger() {
        guard enabled else { return }
        triggerOutstanding = true
        graceDeadline = ProcessInfo.processInfo.systemUptime + Self.graceWindow
        lastCheck = 0 // look on the very next tick rather than waiting out the throttle
        setTimer(Self.searchInterval)
    }

    /// Walks the window list now, whatever the throttle says.
    @discardableResult
    func check() -> Bool {
        guard enabled else { return false }
        lastCheck = ProcessInfo.processInfo.systemUptime
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            if triggerOutstanding && lastCheck > graceDeadline {
                triggerOutstanding = false
                if isActive { setTimer(Self.pollInterval) } else { idle() }
            }
            return isActive
        }

        if KeyboardUtils.isMissionControlActive(list) {
            if !isActive {
                activationID += 1
                // It arrived, so the outstanding trigger was an open.
                triggerOutstanding = false
            } else if triggerOutstanding,
                      ProcessInfo.processInfo.systemUptime > graceDeadline {
                // A trigger that neither arrived nor left by the end of its
                // grace window never will (a modified Escape, an autorepeat)
                // — expire it, or the frame-rate poll never demotes.
                triggerOutstanding = false
            }
            isActive = true
            // Found it — stop searching every frame. Also starts the timer when a
            // caller discovered Mission Control with no trigger behind it. A
            // trigger may still be on its way OUT, though, and the first tick
            // after a closing one sees the close animation, so the fast rate
            // is kept while any trigger is unresolved.
            setTimer(triggerOutstanding ? Self.searchInterval : Self.pollInterval)
            onActive?(list)
        } else if isActive {
            isActive = false
            triggerOutstanding = false
            idle()
            onInactive?()
        } else if lastCheck > graceDeadline {
            triggerOutstanding = false
            idle()
        }
        return isActive
    }

    /// Throttled `check()`, for callers ticking faster than Mission Control changes.
    func checkIfDue() {
        guard enabled,
              ProcessInfo.processInfo.systemUptime - lastCheck >= Self.pollInterval
        else { return }
        check()
    }

    private func setTimer(_ interval: TimeInterval) {
        if let timer, abs(timer.timeInterval - interval) < 0.001 { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.check() }
        }
    }

    private func idle() {
        if detectsUnsignalledOpen {
            setTimer(1)
        } else {
            stopTimer()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
