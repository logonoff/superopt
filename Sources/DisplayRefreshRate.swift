import Cocoa

/// The fastest refresh rate among the active displays.
///
/// Cached rather than queried per tick: `CGDisplayCopyDisplayMode` allocates a
/// mode object per display, which is too much to pay at 120 Hz. The rate only
/// changes with the screen layout, so a notification keeps the cache honest.
/// The maximum is taken across displays so a timer driven by it is never slower
/// than the screen the user is looking at.
@MainActor
enum DisplayRefreshRate {
    private(set) static var current: Double = 60

    /// Seconds per frame, for timers that should tick as often as the screen
    /// can show the result.
    static var frameInterval: TimeInterval { 1.0 / current }

    private static var observer: NSObjectProtocol?

    /// Idempotent — callers start tracking whenever they first need the rate.
    static func startTracking() {
        guard observer == nil else { return }
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { refresh() } }
    }

    private static func refresh() {
        // Displays that don't report a rate come back as 0, so 60 stays the floor.
        var maxRate = 60.0
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        for display in displays {
            if let mode = CGDisplayCopyDisplayMode(display) {
                maxRate = max(maxRate, mode.refreshRate)
            }
        }
        current = maxRate
    }
}
