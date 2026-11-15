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

    /// The appearance of a status item, which is the appearance of the menu bar it sits
    /// in. `AppDelegate` supplies its own rather than this class making a second one.
    var menuBarAppearance: (() -> NSAppearance?)?

    /// Which displays were last seen with a menu bar drawing light text, by display ID.
    private var lightText: [CGDirectDisplayID: Bool] = [:]
    /// When the wallpaper was last changed, as far as the readings above are concerned.
    private var wallpaperChangedAt: Date?

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
        // Display IDs and wallpapers both move around with the screen layout.
        lightText.removeAll()
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

        recordMenuBarAppearance()

        for screen in NSScreen.screens {
            guard let overlay = overlays.first(where: { $0.screenFrame == screen.frame }) else {
                continue
            }
            let filled = isScreenFilled(
                screen, menuBarBottom: overlay.menuBarBottom, windowList: windowList)
            let target: CGFloat = filled && textStaysLegible(on: screen) ? 1 : 0
            let win = overlay.window
            if win.alphaValue != target {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    win.animator().alphaValue = target
                }
            }
        }
    }

    /// Notes what the menu bar on the display being used is drawing. A status item
    /// takes the appearance of the menu bar it sits in, and `NSScreen.main` is the
    /// display that menu bar belongs to, so one display can be read at a time — the
    /// active one. The others are remembered from when they were last active, which
    /// holds while their wallpaper and their windows do.
    private func recordMenuBarAppearance() {
        forgetReadingsIfWallpaperChanged()
        guard let appearance = menuBarAppearance?(),
              let screen = NSScreen.main, let display = Self.displayID(of: screen)
        else { return }
        lightText[display] = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Where macOS keeps the current wallpaper, including the picture a slideshow is
    /// on. Its modification date moves whenever the wallpaper does.
    private static let wallpaperStore =
        ("~/Library/Application Support/com.apple.wallpaper/Store/Index.plist" as NSString)
        .expandingTildeInPath

    /// Drops the readings for displays that are not in use when the wallpaper changes,
    /// since that is what the menu bar takes its colour from. The display in use is
    /// read again on the next tick either way, so only the others go stale, and a
    /// display with no reading is one the bar is not drawn on.
    ///
    /// The date of the file is the signal because there is nothing better to ask:
    /// `NSWorkspace.desktopImageURL(for:)` went on naming the previous picture after
    /// the wallpaper had been changed, on every display.
    private func forgetReadingsIfWallpaperChanged() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: Self.wallpaperStore)
        guard let changedAt = attributes?[.modificationDate] as? Date else { return }
        defer { wallpaperChangedAt = changedAt }
        guard let wallpaperChangedAt, wallpaperChangedAt != changedAt else { return }
        lightText.removeAll()
    }

    /// Whether a bar on this display would leave the menu bar's text readable.
    ///
    /// The menu bar draws its own text in a colour the system picks from what it finds
    /// behind the menu bar — the wallpaper, or the background it puts up for a window
    /// it considers to fill the display. Nothing drawn there changes that choice: a
    /// bar at any window level, down to the desktop, leaves it as it was. So over a
    /// light wallpaper the text is dark, and a black bar behind it would swallow it.
    /// A display that has not been read yet goes by the ones that have: where every
    /// reading says light text the wallpaper is dark all round and the bar is safe,
    /// and one light menu bar anywhere is enough to give the text the benefit of the
    /// doubt until that display has been read for itself.
    private func textStaysLegible(on screen: NSScreen) -> Bool {
        guard let display = Self.displayID(of: screen) else { return false }
        if let reading = lightText[display] { return reading }
        return !lightText.isEmpty && lightText.values.allSatisfy { $0 }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
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
