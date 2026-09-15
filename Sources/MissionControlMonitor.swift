import Cocoa

/// Tracks whether Mission Control is on screen, for the features that need to know.
///
/// Nothing polls while Mission Control is closed. Polling starts from a trigger —
/// the app opening Mission Control itself, or the event tap seeing an F3 — and stops
/// again when Mission Control goes away, or when it never showed up within
/// `graceWindow`. Opening Mission Control some other way (a trackpad swipe, the Dock
/// icon) produces no trigger, so callers that are doing work anyway and can afford a
/// window list walk use `check()` to find it that way instead.
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

    /// True while a trigger is outstanding and Mission Control has yet to appear —
    /// it is on its way in, so a caller that cares is better off looking right now
    /// than waiting for the next poll.
    var isOpening: Bool {
        !isActive && enabled && ProcessInfo.processInfo.systemUptime <= graceDeadline
    }

    func start() {
        enabled = true
        DisplayRefreshRate.startTracking()
    }

    func stop() {
        enabled = false
        stopTimer()
        guard isActive else { return }
        isActive = false
        onInactive?()
    }

    /// Called when something that might have opened Mission Control happened. Entering
    /// or leaving Mission Control with the pointer held still generates no mouse-moved
    /// event, so without this nothing would notice either transition.
    func noteTrigger() {
        guard enabled, !isActive else { return }
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
        else { return isActive }

        if KeyboardUtils.isMissionControlActive(list) {
            if !isActive { activationID += 1 }
            isActive = true
            // Found it — stop searching every frame. Also starts the timer when a
            // caller discovered Mission Control with no trigger behind it.
            setTimer(Self.pollInterval)
            onActive?(list)
        } else if isActive {
            isActive = false
            stopTimer()
            onInactive?()
        } else if lastCheck > graceDeadline {
            stopTimer() // triggered, but Mission Control never appeared
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

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
