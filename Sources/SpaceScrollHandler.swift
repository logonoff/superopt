import Cocoa

/// Scrolling the Apple menu switches space, the way scrolling GNOME's panel switches
/// workspace. The display under the pointer is the one that moves, because that is the
/// display the system's own shortcut acts on.
///
/// Showing where it landed is not this class's job: a space change is worth reporting
/// however it was made, so `SpaceChangeWatcher` does it. The exception is scrolling
/// past either end of the row, which changes nothing and so goes unreported.
@MainActor
final class SpaceScrollHandler {
    /// How far a trackpad gesture travels before it counts as one space.
    private static let threshold: CGFloat = 40
    /// Idle time after which travel is forgotten, so two flicks don't add up.
    private static let gestureGap: TimeInterval = 0.3
    /// Floor on the time between switches, so one long swipe doesn't run the whole row.
    private static let cooldown: TimeInterval = 0.25
    /// How far from the left edge of the menu bar to bother asking what is under the
    /// pointer. The Apple menu is about 33pt wide; this is comfortably past it.
    private static let appleMenuWidth: CGFloat = 60
    /// Height to search when the menu bar is set to auto-hide, where `visibleFrame`
    /// reports no menu bar at all but one can still be pulled down and scrolled.
    private static let hiddenMenuBarHeight: CGFloat = 40
    /// The space list reads stale for roughly this long after a switch is posted (the
    /// animation); an edge computed during that window is the animation talking, not
    /// the row's real end.
    private static let switchSettle: TimeInterval = 1.3

    private var travel: CGFloat = 0
    /// The display whose menu bar `travel` was accumulated against, so a
    /// gesture begun on one display's Apple menu cannot complete on
    /// another's.
    private var travelDisplayID: CGDirectDisplayID = 0
    private var lastScrollAt: TimeInterval = 0
    private var lastSwitchAt: TimeInterval = 0
    /// When a switch was last posted, per display — the stale read is per
    /// display, so the suppression is too.
    private var lastSwitchPostedAt: [String: TimeInterval] = [:]

    /// Called when the scroll lands on a space that is already showing, with the space
    /// count, the index, and the screens it applies to. Every other case is a real
    /// space change, which `SpaceChangeWatcher` reports on its own.
    var onEdge: ((Int, Int, [NSScreen]) -> Void)?

    /// Returns true if the event was consumed.
    func handleScroll(event: CGEvent) -> Bool {
        guard !KeyboardUtils.isSynthetic(event),
              // Momentum arrives long after the fingers leave the trackpad; counting it
              // would turn one flick into a run through every space.
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              let screen = menuBarScreen(under: event.location),
              isOverAppleMenu(event.location, on: screen)
        else { return false }

        // One gesture belongs to one display's menu bar: travel accumulated
        // against another display's Apple menu must not carry over, or a
        // short scroll here completes a gesture begun there.
        let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        if displayID != travelDisplayID {
            travel = 0
            travelDisplayID = displayID
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSwitchAt >= Self.cooldown else { return true }

        guard let direction = direction(of: event, at: now) else { return true }
        travel = 0
        lastSwitchAt = now
        switchSpace(by: direction, on: screen)
        return true
    }

    /// Which way this scroll goes, or nil if it has not asked for a space yet.
    ///
    /// A wheel and a trackpad are read differently. A wheel reports whole notches, and
    /// one notch is one space, as it is in GNOME: its point delta carries the system's
    /// scroll acceleration — around 10pt for an unhurried notch — so measuring distance
    /// there made a slow wheel take four notches to move one space. A trackpad has no
    /// notches to count, so its travel is added up until it amounts to a gesture.
    ///
    /// The sign is taken as the system reports it, after natural scrolling has had its
    /// say, so this reads the same way round as scrolling anything else on the machine —
    /// which is what GNOME does with that setting too. Scrolling up goes to the space on
    /// the left, as scrolling up goes to the top of anything else.
    private func direction(of event: CGEvent, at now: TimeInterval) -> Int? {
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 else {
            let lines = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            guard lines != 0 else { return nil }
            return lines > 0 ? -1 : 1
        }

        if now - lastScrollAt > Self.gestureGap { travel = 0 }
        lastScrollAt = now
        travel += CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        guard abs(travel) >= Self.threshold else { return nil }
        return travel > 0 ? -1 : 1
    }

    private func switchSpace(by direction: Int, on screen: NSScreen) {
        guard let target = SpaceSwitcher.target(for: screen) else { return }
        let display = target.display
        // An unreadable current space carries no position in the row, so the
        // row's end cannot be known and nothing is posted — the same nothing
        // a read that dropped the display used to produce.
        guard display.currentIndex < display.spaceIDs.count else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let lastPosted = lastSwitchPostedAt[display.identifier] ?? 0
        let index = min(max(display.currentIndex + direction, 0), display.spaceIDs.count - 1)

        guard index != display.currentIndex else {
            // Either end of the row. Nothing will move, so no space change is coming
            // for `SpaceChangeWatcher` to report, and this is the only chance to answer
            // "did that do anything" — which GNOME answers here too.
            // Suppressed while a switch from this display is still animating: the
            // stale space list would report an edge — and pop the OSD for the
            // wrong space — for a scroll the system is still acting on.
            if now - lastPosted >= Self.switchSettle {
                onEdge?(display.spaceIDs.count, index, target.screens)
            }
            return
        }
        // The post is always made — dropping it would lose the wheel-spin
        // case if the system honors same-direction posts mid-animation
        // (opposite-direction absorption is what was measured; same-direction
        // was not). Only a post outside the settle window arms the
        // suppression: one made inside it acts on the same switch and its
        // stale read, so it extends nothing.
        if SpaceShortcut.post(direction > 0 ? .right : .left),
           now - lastPosted >= Self.switchSettle {
            // Entries older than the settle window are dead weight; keeping
            // only live ones bounds the dictionary across dock/undock cycles
            // that keep minting display UUIDs.
            lastSwitchPostedAt = lastSwitchPostedAt.filter { now - $0.value < Self.switchSettle }
            lastSwitchPostedAt[display.identifier] = now
        }
    }

    // MARK: - Hit testing

    /// The screen whose menu bar holds this point, near the left edge where the Apple
    /// menu sits. Pure geometry, cheap enough for every scroll event; it is what keeps
    /// the accessibility query below off the common path.
    private func menuBarScreen(under location: CGPoint) -> NSScreen? {
        let point = KeyboardUtils.cgRectToNS(CGRect(origin: location, size: .zero)).origin
        // With "Displays have separate Spaces" off, only the main display has
        // a menu bar — the top strip of the others is ordinary screen space,
        // and treating it as a scrollable Apple menu would consume scrolls
        // aimed at window toolbars and switch spaces with no menu involved.
        let screens = NSScreen.screens
        let candidates = NSScreen.screensHaveSeparateSpaces
            ? screens : Array(screens.prefix(1))
        return candidates.first { screen in
            let menuBarHeight = max(
                screen.frame.maxY - screen.visibleFrame.maxY, Self.hiddenMenuBarHeight)
            return point.y > screen.frame.maxY - menuBarHeight
                && point.y <= screen.frame.maxY
                && point.x >= screen.frame.minX
                && point.x < screen.frame.minX + Self.appleMenuWidth
        }
    }

    /// Whether the Apple menu is under the pointer.
    ///
    /// Asking what sits at the point would be simpler, but `AXUIElementCopyElementAtPosition`
    /// answers with the topmost element, and when the dark menu bar is switched on that
    /// is SuperOpt's own overlay, which covers the whole strip. So this reads the Apple
    /// menu's own frame instead, from the frontmost app's menu bar, where it is the first
    /// item — true in any language, unlike its title. Every display places it the same
    /// distance from the top-left corner, so the frame carries across to whichever
    /// display the pointer is on.
    private func isOverAppleMenu(_ location: CGPoint, on screen: NSScreen) -> Bool {
        guard let frame = appleMenuFrame(),
              // Both axes: vertically stacked displays share an x-range, and
              // resolving the host by x alone picks whichever `NSScreen.screens`
              // lists first — leaving the Apple menu's y-offset off by a full
              // screen height and the feature dead on the other display.
              let host = NSScreen.screens.first(where: { candidate in
                  let origin = cgOrigin(of: candidate)
                  return origin.x <= frame.midX && frame.midX < origin.x + candidate.frame.width
                      && origin.y <= frame.midY && frame.midY < origin.y + candidate.frame.height
              }) ?? NSScreen.main
        else { return false }

        let offset = CGPoint(x: frame.minX - cgOrigin(of: host).x,
                             y: frame.minY - cgOrigin(of: host).y)
        let onThisScreen = CGRect(
            origin: CGPoint(x: cgOrigin(of: screen).x + offset.x,
                            y: cgOrigin(of: screen).y + offset.y),
            size: frame.size)
        return onThisScreen.contains(location)
    }

    private func appleMenuFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef.flatMap(KeyboardUtils.toAXElement) else { return nil }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let apple = (childrenRef as? [AXUIElement])?.first else { return nil }
        return KeyboardUtils.axWindowFrame(apple)
    }

    /// A screen's top-left corner in the flipped coordinates CGEvent locations use.
    private func cgOrigin(of screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.minX, y: KeyboardUtils.primaryScreenHeight() - screen.frame.maxY)
    }
}
