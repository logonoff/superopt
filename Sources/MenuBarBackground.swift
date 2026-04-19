import Cocoa

private class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

class MenuBarBackground: NSObject {
    private var windows: [NSWindow] = []
    private var timer: Timer?
    private var active = false

    func start() {
        active = true
        if timer == nil {
            if windows.isEmpty { createWindows() }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.update()
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(screenChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil
            )
        }
        update()
    }

    @objc private func screenChanged() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        createWindows()
        update()
    }

    func stop() {
        active = false
        for w in windows {
            w.alphaValue = 0
        }
    }

    private func createWindows() {
        for screen in NSScreen.screens {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            guard menuBarHeight > 0 else { continue }

            let window = UnconstrainedWindow(
                contentRect: .zero,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .black
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.orderFrontRegardless()

            let frame = NSRect(
                x: screen.frame.origin.x,
                y: screen.visibleFrame.maxY,
                width: screen.frame.width,
                height: menuBarHeight
            )
            window.setFrame(frame, display: true)
            window.setFrameOrigin(NSPoint(x: screen.frame.origin.x, y: screen.visibleFrame.maxY))

            windows.append(window)
        }
    }

    private func update() {
        if !active {
            for w in windows { w.alphaValue = 0 }
            return
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        // Hide when Mission Control is active — Dock creates overlay windows at high layers
        let missionControlActive = windowList.contains { info in
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  let layer = info[kCGWindowLayer as String] as? Int else { return false }
            return owner == "Dock" && layer > 0
        }
        if missionControlActive {
            for w in windows { w.alphaValue = 0 }
            return
        }

        let screens = NSScreen.screens
        for (i, screen) in screens.enumerated() {
            guard i < windows.count else { break }
            let filled = isScreenFilled(screen, windowList: windowList)
            let target: CGFloat = filled ? 1 : 0
            if windows[i].alphaValue != target {
                let w = windows[i]
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    w.animator().alphaValue = target
                }
            }
        }
    }

    private func isScreenFilled(_ screen: NSScreen, windowList: [[String: Any]]) -> Bool {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != ProcessInfo.processInfo.processIdentifier
            else { continue }

            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgW = boundsDict["Width"] ?? 0
            let cgH = boundsDict["Height"] ?? 0

            let nsY = primaryHeight - cgY - cgH
            let windowFrame = NSRect(x: cgX, y: nsY, width: cgW, height: cgH)

            let usableArea = NSRect(
                x: screen.frame.origin.x,
                y: screen.frame.origin.y,
                width: screen.frame.width,
                height: screen.frame.height - menuBarHeight
            )

            if windowFrame.minX <= usableArea.minX + 2
                && windowFrame.minY <= usableArea.minY + 2
                && windowFrame.maxX >= usableArea.maxX - 2
                && windowFrame.maxY >= usableArea.maxY - 2
            {
                return true
            }
        }
        return false
    }
}
