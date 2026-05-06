import Cocoa

private let skylight = dlopen(nil, RTLD_LAZY)
@MainActor
class MissionControlCloseHandler {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias ScreenRectFn = @convention(c) (Int32, UInt32, UnsafeMutablePointer<CGRect>) -> Int32
    private let cid: Int32
    private let getScreenRect: ScreenRectFn

    private var enabled = false
    private(set) var mcActive = false
    private var lastCheckTime: TimeInterval = 0
    private let checkInterval: TimeInterval = 0.25
    private var cachedRefreshRate: Double = 60.0
    private var overlay: CloseOverlay?
    private var hoveredWID: UInt32 = 0
    private var buttonHovered = false
    private var positionTimer: Timer?
    private var lastOverlayOrigin = NSPoint.zero
    private var stableFrames = 0

    private struct WindowEntry {
        let wid: UInt32
        let pid: pid_t
        let rect: CGRect
    }

    private var windowRects: [WindowEntry] = []
    private var ghostRects: [WindowEntry] = []
    private var unclosableWIDs: Set<UInt32> = []
    private var closableWIDs: Set<UInt32> = []
    private var recentlyClosedWIDs: Set<UInt32> = []

    private static let buttonSize: CGFloat = 26
    private static let hitPadding: CGFloat = 9

    init?() {
        // Private: CGSGetScreenRectForWindow returns the on-screen compositor bounds
        // of a window (the scaled thumbnail position during Mission Control).
        // CGWindowListCopyWindowInfo only reports logical frames, which don't update
        // during MC's scaling transform — no public API exposes compositor geometry.
        guard let cidPtr = dlsym(skylight, "CGSMainConnectionID"),
              let srPtr = dlsym(skylight, "CGSGetScreenRectForWindow")
        else { return nil }
        cid = unsafeBitCast(cidPtr, to: MainConnFn.self)()
        getScreenRect = unsafeBitCast(srPtr, to: ScreenRectFn.self)
    }

    private var screenObserver: NSObjectProtocol?

    func start() {
        enabled = true
        updateCachedRefreshRate()
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCachedRefreshRate() }
            }
        }
    }

    func stop() {
        enabled = false; deactivateMC()
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }

    private func updateCachedRefreshRate() {
        var maxRate = 60.0
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        for display in displays {
            if let mode = CGDisplayCopyDisplayMode(display) {
                maxRate = max(maxRate, mode.refreshRate)
            }
        }
        cachedRefreshRate = maxRate
    }

    private func setTimerRate(fast: Bool) {
        let interval: TimeInterval = fast ? 1.0 / cachedRefreshRate : 0.25
        if let existing = positionTimer, abs(existing.timeInterval - interval) < 0.01 {
            return
        }
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOverlay() }
        }
    }

    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
        stableFrames = 0
    }

    private func closeButtonCGRect(for windowRect: CGRect) -> CGRect {
        let half = Self.buttonSize / 2
        return CGRect(
            x: windowRect.maxX - half, y: windowRect.origin.y - half,
            width: Self.buttonSize, height: Self.buttonSize)
    }

    private func hitTestCGRect(for windowRect: CGRect) -> CGRect {
        closeButtonCGRect(for: windowRect).insetBy(
            dx: -Self.hitPadding, dy: -Self.hitPadding)
    }

    // MARK: - Event tap hooks

    func handleClick(event: CGEvent) -> Bool {
        guard mcActive else { return false }
        let loc = event.location
        if ghostRects.contains(where: { $0.rect.contains(loc) }) { return true }
        guard hoveredWID != 0,
              let entry = windowRects.first(where: { $0.wid == hoveredWID }),
              hitTestCGRect(for: entry.rect).contains(loc)
        else { return false }
        closeWindow(pid: entry.pid, windowID: entry.wid, cursorLocation: loc)
        return true
    }

    @discardableResult
    func handleMouseMoved(event: CGEvent) -> Bool {
        guard enabled, !KeyboardUtils.isSynthetic(event) else { return false }
        let loc = event.location

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCheckTime >= checkInterval {
            lastCheckTime = now
            if checkMCState() { return false }
        }
        guard mcActive else { return false }

        if ghostRects.contains(where: { $0.rect.contains(loc) }) { return true }

        let hitWID = windowRects.first(where: { $0.rect.contains(loc) })?.wid ?? 0
        let overButton: Bool
        if hitWID != 0, let entry = windowRects.first(where: { $0.wid == hitWID }) {
            overButton = hitTestCGRect(for: entry.rect).contains(loc)
        } else {
            overButton = false
        }

        let changed = hitWID != hoveredWID || overButton != buttonHovered
        hoveredWID = hitWID
        buttonHovered = overButton
        if changed {
            updateOverlay()
            if hoveredWID != 0 {
                stableFrames = 0; setTimerRate(fast: true)
            } else {
                stopPositionTimer()
            }
        }
        return false
    }

    private func checkMCState() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return false }
        if KeyboardUtils.isMissionControlActive(windowList) {
            mcActive = true
            refreshWindowRects(from: windowList)
            return false
        } else if mcActive {
            deactivateMC()
            return true
        }
        return false
    }

    private func deactivateMC() {
        mcActive = false; hoveredWID = 0; buttonHovered = false
        stopPositionTimer(); hideOverlay()
        windowRects.removeAll(); ghostRects.removeAll()
        unclosableWIDs.removeAll(); closableWIDs.removeAll()
        recentlyClosedWIDs.removeAll()
    }

    private func refreshWindowRects(from windowList: [[String: Any]]) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        var rects: [WindowEntry] = []
        for info in windowList {
            guard let wid = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID, !unclosableWIDs.contains(wid),
                  !recentlyClosedWIDs.contains(wid)
            else { continue }
            var screenRect = CGRect.zero
            guard getScreenRect(cid, wid, &screenRect) == 0,
                  screenRect.width > 60, screenRect.height > 60 else { continue }
            if !closableWIDs.contains(wid) {
                guard let axWin = KeyboardUtils.findAXWindow(pid: pid, windowID: wid),
                      let btn = axCloseButton(of: axWin),
                      axIsEnabled(btn)
                else { unclosableWIDs.insert(wid); continue }
                closableWIDs.insert(wid)
            }
            rects.append(WindowEntry(wid: wid, pid: pid, rect: screenRect))
        }
        windowRects = rects
    }

    // MARK: - Overlay

    private func updateOverlay() {
        guard hoveredWID != 0 else { hideOverlay(); return }
        var liveRect = CGRect.zero
        guard getScreenRect(cid, hoveredWID, &liveRect) == 0,
              liveRect.width > 60, liveRect.height > 60
        else { hideOverlay(); return }
        let cgBtn = closeButtonCGRect(for: liveRect)
        let origin = KeyboardUtils.cgRectToNS(cgBtn).origin
        let moved = abs(origin.x - lastOverlayOrigin.x) > 0.5
            || abs(origin.y - lastOverlayOrigin.y) > 0.5
        lastOverlayOrigin = origin

        if moved {
            stableFrames = 0
            setTimerRate(fast: true)
        } else {
            stableFrames += 1
            if stableFrames > Int(cachedRefreshRate * 2) { setTimerRate(fast: false) }
        }

        if let existing = overlay {
            existing.reposition(origin: origin)
            existing.setState(hovered: buttonHovered)
        } else {
            overlay = CloseOverlay(
                origin: origin, size: Self.buttonSize, hovered: buttonHovered)
        }
    }

    private func hideOverlay() { overlay?.close(); overlay = nil }
}

// MARK: - AX helpers

extension MissionControlCloseHandler {
    fileprivate func axCloseButton(of window: AXUIElement) -> AXUIElement? {
        var ref: AnyObject?
        AXUIElementCopyAttributeValue(
            window, kAXCloseButtonAttribute as CFString, &ref)
        return ref.flatMap(KeyboardUtils.toAXElement)
    }

    fileprivate func closeWindow(pid: pid_t, windowID: UInt32, cursorLocation: CGPoint = .zero) {
        guard let win = KeyboardUtils.findAXWindow(pid: pid, windowID: windowID),
              let btn = axCloseButton(of: win) else { return }
        var screenRect = CGRect.zero
        _ = getScreenRect(cid, windowID, &screenRect)
        AXUIElementPerformAction(btn, kAXPressAction as CFString)
        hoveredWID = 0; hideOverlay()
        closableWIDs.remove(windowID)
        recentlyClosedWIDs.insert(windowID)
        windowRects.removeAll(where: { $0.wid == windowID })
        if screenRect.width > 0 {
            ghostRects.append(WindowEntry(wid: windowID, pid: pid, rect: screenRect))
            nudgeMouseOff(screenRect, from: cursorLocation)
        }
    }

    private func warpAndPost(_ point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private func nudgeMouseOff(_ rect: CGRect, from point: CGPoint) {
        let primaryHeight = KeyboardUtils.primaryScreenHeight()
        let nsPoint = NSPoint(x: point.x, y: primaryHeight - point.y)
        let screenFrame = NSScreen.screens.first(where: {
            $0.frame.contains(nsPoint)
        })?.frame ?? NSScreen.main?.frame ?? .zero
        let screenCG = CGRect(
            x: screenFrame.origin.x, y: primaryHeight - screenFrame.maxY,
            width: screenFrame.width, height: screenFrame.height)

        let offset: CGFloat = 20
        var nudged = point
        let rightNudge = rect.maxX + offset
        let leftNudge = rect.minX - offset
        if rightNudge <= screenCG.maxX {
            nudged.x = rect.maxX + offset
        } else if leftNudge >= screenCG.minX {
            nudged.x = rect.minX - offset
        } else {
            nudged.y = rect.maxY + offset <= screenCG.maxY
                ? rect.maxY + offset : rect.minY - offset
        }
        warpAndPost(nudged)
        DispatchQueue.main.asyncAfter(deadline: .now()) {
            MainActor.assumeIsolated { self.warpAndPost(point) }
        }
    }

    fileprivate func axIsEnabled(_ element: AXUIElement) -> Bool {
        var val: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &val)
        return (val as? Bool) != false
    }
}
