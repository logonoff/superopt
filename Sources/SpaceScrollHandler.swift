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
    /// How far a gesture travels before it counts as one space.
    private static let threshold: CGFloat = 40
    /// A wheel reports lines where a trackpad reports points. One line per space keeps
    /// a single detent of a wheel worth one space.
    private static let pointsPerLine: CGFloat = threshold
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

    private var travel: CGFloat = 0
    private var lastScrollAt: TimeInterval = 0
    private var lastSwitchAt: TimeInterval = 0

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

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScrollAt > Self.gestureGap { travel = 0 }
        lastScrollAt = now
        travel += scrollDelta(of: event)

        guard abs(travel) >= Self.threshold, now - lastSwitchAt >= Self.cooldown else { return true }
        // Scrolling up goes to the space on the left, as scrolling up goes to the top
        // of anything else.
        let direction = travel > 0 ? -1 : 1
        travel = 0
        lastSwitchAt = now
        switchSpace(by: direction, on: screen)
        return true
    }

    /// How far the gesture has moved, in points.
    ///
    /// Trackpads report points; a wheel reports lines and leaves the point fields at 0.
    /// The sign is taken as the system reports it, after natural scrolling has had its
    /// say, so the gesture reads the same way round as scrolling anything else on the
    /// machine — which is also what GNOME does with the setting.
    private func scrollDelta(of event: CGEvent) -> CGFloat {
        let points = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        if points != 0 { return CGFloat(points) }
        return CGFloat(event.getDoubleValueField(.scrollWheelEventDeltaAxis1)) * Self.pointsPerLine
    }

    private func switchSpace(by direction: Int, on screen: NSScreen) {
        guard let target = SpaceSwitcher.target(for: screen) else { return }
        let display = target.display
        let index = min(max(display.currentIndex + direction, 0), display.spaceIDs.count - 1)

        guard index != display.currentIndex else {
            // Either end of the row. Nothing will move, so no space change is coming
            // for `SpaceChangeWatcher` to report, and this is the only chance to answer
            // "did that do anything" — which GNOME answers here too.
            onEdge?(display.spaceIDs.count, index, target.screens)
            return
        }
        SpaceShortcut.post(direction > 0 ? .right : .left)
    }

    // MARK: - Hit testing

    /// The screen whose menu bar holds this point, near the left edge where the Apple
    /// menu sits. Pure geometry, cheap enough for every scroll event; it is what keeps
    /// the accessibility query below off the common path.
    private func menuBarScreen(under location: CGPoint) -> NSScreen? {
        let point = KeyboardUtils.cgRectToNS(CGRect(origin: location, size: .zero)).origin
        return NSScreen.screens.first { screen in
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
              let host = NSScreen.screens.first(where: {
                  $0.frame.minX <= frame.midX && frame.midX < $0.frame.maxX
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
