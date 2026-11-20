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

    private func handleCleanOptionRelease() {
        let now = ProcessInfo.processInfo.systemUptime

        singlePressWorkItem?.cancel()
        singlePressWorkItem = nil

        if now - lastCleanOptionUpTime < doublePressThreshold {
            lastCleanOptionUpTime = 0
            onDoublePress?()
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
