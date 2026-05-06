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
    var onTile: ((SnapAssistPanel.TileDirection, NSScreen) -> Void)?
    var isPanelVisible: () -> Bool = { false }

    private var observer: AXObserver?
    private var watchedWindow: AXUIElement?
    private var watchedPID: pid_t = -1
    private var previousFrame: CGRect = .zero
    private var previousWasTiled = false
    private var appObserver: NSObjectProtocol?
    private var selfPtr: Unmanaged<TileAssistWatcher>?
    private var debounceTimer: Timer?
    private var suppressUntil: TimeInterval = 0
    private static let tolerance: CGFloat = 10

    func suppress() { suppressUntil = ProcessInfo.processInfo.systemUptime + 1.5 }

    func start() {
        guard selfPtr == nil else { return }
        selfPtr = Unmanaged.passRetained(self)
        observeFrontmostApp()
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.observeFrontmostApp() } }
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
        tearDownObserver()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        watchedPID = pid

        let axApp = AXUIElementCreateApplication(pid)
        var winRef: AnyObject?
        AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &winRef)
        guard let window = winRef.flatMap(KeyboardUtils.toAXElement) else { return }
        watchedWindow = window
        previousFrame = Self.windowFrame(window)
        previousWasTiled = Self.tileDirection(
            previousFrame, onScreen: Self.screenForWindow(previousFrame)) != nil

        var obs: AXObserver?
        guard AXObserverCreate(
            pid, tileWatcherCallback, &obs) == .success,
              let obs else { return }
        observer = obs
        let refcon = selfPtr?.toOpaque()
        for note in [kAXMovedNotification, kAXResizedNotification] as [CFString] {
            AXObserverAddNotification(obs, window, note, refcon)
        }
        AXObserverAddNotification(
            obs, axApp,
            kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    func windowDidChange() {
        let axApp = AXUIElementCreateApplication(watchedPID)
        var winRef: AnyObject?
        AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &winRef)
        guard let window = winRef.flatMap(KeyboardUtils.toAXElement) else { return }

        if window != watchedWindow {
            debounceTimer?.invalidate(); debounceTimer = nil
            tearDownObserver()
            observeFrontmostApp()
            return
        }

        let frame = Self.windowFrame(window)
        guard frame != previousFrame else { return }
        previousFrame = frame

        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTileState() }
        }
    }

    private func checkTileState() {
        guard let window = watchedWindow,
              ProcessInfo.processInfo.systemUptime > suppressUntil
        else { return }
        let frame = Self.windowFrame(window)
        previousFrame = frame
        let screen = Self.screenForWindow(frame)
        let dir = Self.tileDirection(frame, onScreen: screen)
        let wasTiled = previousWasTiled
        previousWasTiled = dir != nil

        if !wasTiled, let dir, let screen, !isPanelVisible(),
           !Self.isOtherHalfOccupied(direction: dir, screen: screen) {
            onTile?(dir, screen)
        }
    }

    private func tearDownObserver() {
        if let obs = observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(obs), .defaultMode)
            observer = nil
        }
        watchedWindow = nil
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
