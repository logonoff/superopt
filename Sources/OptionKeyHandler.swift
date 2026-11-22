import Cocoa

@MainActor
class OptionKeyHandler {
    var onSinglePress: (() -> Void)?
    var onDoublePress: (() -> Void)?

    private var optionIsDown = false
    private var otherInputDetected = false
    /// Whether the press being held began while the active app was
    /// excluded. Such a press belongs to that app, not to SuperOpt, so its
    /// release must not fire even when it lands after leaving.
    private var pressWasSuspended = false
    private var lastCleanOptionUpTime: TimeInterval = 0
    /// The last release of the current double-press burst — set by the double
    /// itself and extended by every tail release, so a burst of any length is
    /// recognised as one gesture.
    private var doubleFiredAt: TimeInterval = 0
    private var singlePressWorkItem: DispatchWorkItem?

    private let doublePressThreshold: TimeInterval = 0.3

    /// Whether the press actions may fire. State is tracked even while the
    /// active app is excluded — the release of a chord held into it has to
    /// be seen, or stale flags misjudge the next press after leaving — but
    /// the actions are suspended there along with everything else.
    /// - Parameter actionsEnabled: false while the active app is excluded.
    func handleFlagsChanged(event: CGEvent, actionsEnabled: Bool) {
        let flags = event.flags
        let optionCurrentlyDown = flags.contains(.maskAlternate)
        let hasOtherModifiers =
            flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskShift)

        if optionCurrentlyDown && !optionIsDown {
            optionIsDown = true
            otherInputDetected = hasOtherModifiers
            pressWasSuspended = !actionsEnabled
            if !pressWasSuspended {
                // A second press supersedes the first one's pending single-press
                // timer — clean or chorded. Without this, a double press whose
                // second hold outlasts the threshold, or a quick roll into an
                // ⌥-chord, fires the single-press action while Option is already
                // down again. A press from inside an excluded app does not
                // supersede anything: it belongs to that app, and cancelling
                // here would swallow the action the earlier press earned.
                singlePressWorkItem?.cancel()
                singlePressWorkItem = nil
            }

        } else if !optionCurrentlyDown && optionIsDown {
            optionIsDown = false

            if !otherInputDetected && !hasOtherModifiers && !pressWasSuspended && actionsEnabled {
                handleCleanOptionRelease()
            }

        } else if optionIsDown && hasOtherModifiers {
            otherInputDetected = true
        }
    }

    func markOtherInput() {
        if optionIsDown { otherInputDetected = true }
    }

    /// Resynchronises the latch with the live modifier state after the event
    /// tap has been down. A release the tap never saw (secure input took it
    /// down, or it was disabled) leaves `optionIsDown` stale, and the next
    /// unrelated `flagsChanged` — a Caps Lock toggle carries no modifiers —
    /// would read as a clean release and toggle Mission Control out of
    /// nowhere. A press or release this handler could not observe earns no
    /// action: the transition is adopted without firing, the same rule the
    /// Caps Lock latch's resync follows.
    func resync() {
        let optionDown = NSEvent.modifierFlags.contains(.option)
        if optionDown != optionIsDown {
            optionIsDown = optionDown
            otherInputDetected = true
            pressWasSuspended = false
        }
    }

    private func handleCleanOptionRelease() {
        let now = ProcessInfo.processInfo.systemUptime

        singlePressWorkItem?.cancel()
        singlePressWorkItem = nil

        if now - lastCleanOptionUpTime < doublePressThreshold {
            lastCleanOptionUpTime = 0
            doubleFiredAt = now
            onDoublePress?()
        } else if now - doubleFiredAt < doublePressThreshold {
            // The tail of a rapid burst: it already fired its double press,
            // and treating this release as a fresh first press would arm a
            // single-press action on top of it — two conflicting panels
            // from one gesture. Each tail extends the window, so a fourth
            // or fifth tap is still the same burst, not a new first press.
            doubleFiredAt = now
        } else {
            lastCleanOptionUpTime = now
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.onSinglePress?() }
            }
            singlePressWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doublePressThreshold, execute: work)
        }
    }
}
