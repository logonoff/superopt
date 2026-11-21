import Cocoa

private func tileWatcherCallback(
    _: AXObserver, _: AXUIElement, _: CFString, refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<TileAssistWatcher>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.windowDidChange() }
}

@MainActor
class TileAssistWatcher {
    var onTile: ((SnapAssistPanel.TileDirection, NSScreen, TiledWindowInfo) -> Void)?
    var onWindowChange: ((pid_t, CGRect?) -> Void)?

    private var observer: AXObserver?
    private var watchedWindow: AXUIElement?
    private var watchedPID: pid_t = -1
    private var observesWindowChanges = false
    private var previousFrame: CGRect = .zero
    /// The half and screen the window was last tiled on, nil when it was not
    /// tiled. Recording *where* the window is tiled, not just that it is,
    /// keeps a nudge within the same half from re-offering the popup while
    /// still treating a move to the other half — or another screen's half —
    /// as the fresh tile it is.
    private var lastTile: TileState?
    private var appObserver: NSObjectProtocol?
    private var selfPtr: Unmanaged<TileAssistWatcher>?
    private var debounceTimer: Timer?
    private var suppressUntil: TimeInterval = 0
    private static let tolerance: CGFloat = 10

    /// A tiled window's half and the screen it sits on, compared across
    /// checks to decide what counts as a fresh tile.
    private struct TileState: Equatable {
        let direction: SnapAssistPanel.TileDirection
        let screenFrame: NSRect
    }

    func suppress() { suppressUntil = ProcessInfo.processInfo.systemUptime + 1.5 }

    func start() {
        guard selfPtr == nil else { return }
        selfPtr = Unmanaged.passRetained(self)
        observeFrontmostApp()
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                // `frontmostApplication` still names the outgoing app inside
                // this notification (measured; see AGENTS.md), so the
                // activated app comes from the notification itself — reading
                // the property here would leave the observer one app switch
                // behind, re-observing the app the user just left.
                guard let self else { return }
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication {
                    self.observe(app)
                } else {
                    self.observeFrontmostApp()
                }
            }
        }
    }

    func stop() {
        debounceTimer?.invalidate(); debounceTimer = nil
        tearDownObserver()
        if let obs = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appObserver = nil
        }
        if let ptr = selfPtr { ptr.release(); selfPtr = nil }
    }

    func observeFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        observe(app)
    }

    func observe(_ app: NSRunningApplication) {
        tearDownObserver()
        let pid = app.processIdentifier
        watchedPID = pid

        var obs: AXObserver?
        guard AXObserverCreate(
            pid, tileWatcherCallback, &obs) == .success,
              let obs else { return }
        observer = obs
        let refcon = selfPtr?.toOpaque()
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs), .defaultMode)

        let axApp = AXUIElementCreateApplication(pid)
        // The app-level notification is the recovery path for a transient
        // focused-window failure below, so it is registered before that
        // failure can happen — an observer with no notifications registered
        // observes nothing, and the watcher would stay deaf to the app until
        // the next activation.
        let focusResult = AXObserverAddNotification(
            obs, axApp, kAXFocusedWindowChangedNotification as CFString, refcon)

        var winRef: AnyObject?
        AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &winRef)
        guard let window = winRef.flatMap(KeyboardUtils.toAXElement) else { return }
        watchedWindow = window
        previousFrame = Self.windowFrame(window)
        if let screen = Self.screenForWindow(previousFrame),
           let dir = Self.tileDirection(previousFrame, onScreen: screen) {
            lastTile = TileState(direction: dir, screenFrame: screen.frame)
        } else {
            lastTile = nil
        }

        let moveResult = AXObserverAddNotification(obs, window, kAXMovedNotification as CFString, refcon)
        let resizeResult = AXObserverAddNotification(obs, window, kAXResizedNotification as CFString, refcon)
        observesWindowChanges = focusResult == .success && moveResult == .success && resizeResult == .success
    }

    func windowDidChange() {
        let axApp = AXUIElementCreateApplication(watchedPID)
        var winRef: AnyObject?
        AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &winRef)
        guard let window = winRef.flatMap(KeyboardUtils.toAXElement) else { return }

        if window != watchedWindow {
            onWindowChange?(watchedPID, nil)
            debounceTimer?.invalidate(); debounceTimer = nil
            tearDownObserver()
            observeFrontmostApp()
            return
        }

        let frame = Self.windowFrame(window)
        guard frame != .zero, frame != previousFrame else { return }
        onWindowChange?(watchedPID, frame)
        previousFrame = frame

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTileState() }
        }
    }

    private func checkTileState() {
        guard let window = watchedWindow else { return }
        let frame = Self.windowFrame(window)
        // A failed AX read reports .zero — not evidence the window moved or
        // stopped being tiled — and recording it would clear the latch that
        // keeps a nudge of a still-tiled window from re-offering the popup.
        guard frame != .zero else { return }
        previousFrame = frame
        guard let screen = Self.screenForWindow(frame) else { return }
        var currentTile: TileState?
        if let dir = Self.tileDirection(frame, onScreen: screen) {
            currentTile = TileState(direction: dir, screenFrame: screen.frame)
        }
        let newlyTiled = currentTile != nil && currentTile != lastTile
        // Recorded even while suppressed: when Tile Assist itself arranges a
        // window, the move/resize notifications land inside the suppression
        // window, and leaving the state unrecorded there would let a later
        // nudge of the still-tiled window read as a fresh tile and re-offer
        // the popup beside it.
        lastTile = currentTile

        guard ProcessInfo.processInfo.systemUptime > suppressUntil else { return }

        if newlyTiled, let currentTile,
           !Self.isOtherHalfOccupied(direction: currentTile.direction, screen: screen) {
            // The tiled window's identity is handed over as known here: the
            // panel re-identifying it from the frontmost app at popup time
            // races a focus change in the debounce window. A panel still
            // standing from an earlier tile is replaced, not waited out:
            // the free half changed, so its candidates would arrange into
            // the half this window just took — and the panel's own arrange
            // cannot re-trigger this, as it runs inside the suppression
            // window.
            onTile?(currentTile.direction, screen, TiledWindowInfo(
                pid: watchedPID,
                windowID: Self.windowID(of: window),
                frame: frame,
                observesWindowChanges: observesWindowChanges))
        }
    }

    /// The watched window's CGWindowID, 0 when it cannot be had.
    private static func windowID(of window: AXUIElement) -> UInt32 {
        guard let getWindow = KeyboardUtils.axGetWindow else { return 0 }
        var wid: UInt32 = 0
        return getWindow(window, &wid) == 0 ? wid : 0
    }

    private func tearDownObserver() {
        if let obs = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(obs), .defaultMode)
            observer = nil
        }
        watchedWindow = nil
        observesWindowChanges = false
    }
}

// MARK: - Tiling detection

extension TileAssistWatcher {
    fileprivate static func windowFrame(_ window: AXUIElement) -> CGRect {
        KeyboardUtils.axWindowFrame(window)
    }

    fileprivate static func screenForWindow(_ cgFrame: CGRect) -> NSScreen? {
        let nsFrame = KeyboardUtils.cgRectToNS(cgFrame)
        return NSScreen.screens.first { $0.frame.contains(
            NSPoint(x: nsFrame.midX, y: nsFrame.midY)) } ?? NSScreen.main
    }

    fileprivate static func isOtherHalfOccupied(
        direction: SnapAssistPanel.TileDirection, screen: NSScreen
    ) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let opposite: SnapAssistPanel.TileDirection = direction == .left ? .right : .left
        let myPID = ProcessInfo.processInfo.processIdentifier
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let originX = bounds["X"], let originY = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width > 100, height > 100
            else { continue }
            let cgFrame = CGRect(x: originX, y: originY, width: width, height: height)
            guard let winScreen = screenForWindow(cgFrame),
                  winScreen.frame == screen.frame else { continue }
            if tileDirection(cgFrame, onScreen: screen) == opposite { return true }
        }
        return false
    }

    fileprivate static func tileDirection(
        _ cgFrame: CGRect, onScreen screen: NSScreen?
    ) -> SnapAssistPanel.TileDirection? {
        guard let screen else { return nil }
        let nsFrame = KeyboardUtils.cgRectToNS(cgFrame)
        let visible = screen.visibleFrame

        guard nsFrame.minY <= visible.minY + tolerance,
              nsFrame.maxY >= visible.maxY - tolerance,
              nsFrame.width < visible.width - 50
        else { return nil }

        if nsFrame.minX <= visible.minX + tolerance {
            return .left
        }
        if nsFrame.maxX >= visible.maxX - tolerance {
            return .right
        }
        return nil
    }
}
