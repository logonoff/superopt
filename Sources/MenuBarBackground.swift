import Cocoa

private class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

private struct Overlay {
    let window: NSWindow
    let screenFrame: NSRect

    /// Bottom edge of the menu bar strip, in NSScreen coordinates.
    var menuBarBottom: CGFloat { window.frame.minY }
}

@MainActor
class MenuBarBackground: NSObject {
    private var overlays: [Overlay] = []
    private var timer: Timer?
    private var active = false

    func start() {
        active = true
        if timer == nil {
            if overlays.isEmpty { createWindows() }
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
            NotificationCenter.default.addObserver(
                self, selector: #selector(screenChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil
            )
        }
        update()
    }

    @objc private func screenChanged() {
        for overlay in overlays { overlay.window.orderOut(nil) }
        overlays.removeAll()
        createWindows()
        update()
    }

    func stop() {
        active = false
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        for overlay in overlays {
            overlay.window.alphaValue = 0
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

            overlays.append(Overlay(window: window, screenFrame: screen.frame))
        }
    }

    private func update() {
        if !active {
            for overlay in overlays { overlay.window.alphaValue = 0 }
            return
        }

        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        if KeyboardUtils.isMissionControlActive(windowList) {
            for overlay in overlays { overlay.window.alphaValue = 0 }
            return
        }

        for screen in NSScreen.screens {
            guard let overlay = overlays.first(where: { $0.screenFrame == screen.frame }) else {
                continue
            }
            let filled = isScreenFilled(
                screen, menuBarBottom: overlay.menuBarBottom, windowList: windowList)
            let target: CGFloat = filled ? 1 : 0
            let win = overlay.window
            if win.alphaValue != target {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    win.animator().alphaValue = target
                }
            }
        }
    }

    private func isScreenFilled(
        _ screen: NSScreen, menuBarBottom: CGFloat, windowList: [[String: Any]]
    ) -> Bool {
        let usableArea = screen.visibleFrame

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID != ProcessInfo.processInfo.processIdentifier
            else { continue }

            let cgRect = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            let windowFrame = KeyboardUtils.cgRectToNS(cgRect)

            // A window reaching into the menu bar strip is in full screen, or is hiding the
            // menu bar some other way, and draws those pixels itself — a bar there would
            // cover its content. The strip is the overlay's own frame, so the test is
            // against the rect actually being painted.
            guard windowFrame.maxY <= menuBarBottom + 2 else { continue }

            if windowFrame.minX <= usableArea.minX + 2
                && windowFrame.minY <= usableArea.minY + 2
                && windowFrame.maxX >= usableArea.maxX - 2
                && windowFrame.maxY >= usableArea.maxY - 2 {
                return true
            }
        }
        return false
    }
}
