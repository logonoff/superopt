import Cocoa

/// A GNOME-style on-screen display: a glass pill that fades in over the lower part of
/// a screen, holds, and fades out. It owns the windows and the timing; what goes
/// inside is up to the caller.
///
/// Windows are kept while the panel is up, so a second `show` before the first has
/// faded updates the contents in place rather than restarting the fade.
@MainActor
final class OSDPanel {
    private let displayDuration: TimeInterval
    private let fadeDuration: TimeInterval

    private var windows: [NSWindow] = []
    private var shownSize: NSSize = .zero
    private var shownFrames: [NSRect] = []
    private var dismissWorkItem: DispatchWorkItem?

    init(displayDuration: TimeInterval, fadeDuration: TimeInterval) {
        self.displayDuration = displayDuration
        self.fadeDuration = fadeDuration
    }

    /// Shows a pill of `size` on each of `screens`, filling it by way of `content`,
    /// which is handed the view inside the pill. `announcement` is what VoiceOver says.
    func show(
        size: NSSize, on screens: [NSScreen], announcement: String?,
        content: (NSView) -> Void
    ) {
        dismissWorkItem?.cancel()

        let frames = screens.map(\.frame)
        if size != shownSize || frames != shownFrames {
            for window in windows { window.orderOut(nil) }
            windows = screens.map { window(size: size, on: $0) }
            shownSize = size
            shownFrames = frames
        }

        for window in windows {
            if let view = (window.contentView as? NSGlassEffectView)?.contentView {
                content(view)
            }
            fade(window, to: 1)
        }

        if let announcement {
            NSAccessibility.post(
                element: NSApp as Any, notification: .announcementRequested,
                userInfo: [.announcement: announcement])
        }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }

    private func window(size: NSSize, on screen: NSScreen) -> NSWindow {
        // Above the bottom of the screen rather than dead centre, which is where GNOME
        // puts its own OSDs and keeps the pill clear of whatever is being worked on.
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.12,
            width: size.width, height: size.height)

        let window = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        // Above the menu bar, as the ripple is: an OSD that a full-screen window or the
        // menu bar can cover is not doing its job.
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.hasShadow = false
        // A panel reporting on a space switch has to outlive the switch.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        if let clearStyle = NSGlassEffectView.Style(rawValue: 1) { glass.style = clearStyle }
        glass.cornerRadius = 9999
        glass.contentView = NSView(frame: NSRect(origin: .zero, size: size))

        window.contentView = glass
        window.alphaValue = 0
        window.orderFrontRegardless()
        return window
    }

    private func fade(_ window: NSWindow, to alpha: CGFloat) {
        guard window.alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            window.animator().alphaValue = alpha
        }
    }

    private func dismiss() {
        for window in windows {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = fadeDuration
                window.animator().alphaValue = 0
            }, completionHandler: { window.orderOut(nil) })
        }
        windows = []
        shownSize = .zero
        shownFrames = []
    }
}
