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
    /// Per-window fade generation, bumped by every fade so a delayed fallback
    /// whose fade was superseded (a re-show or dismissal mid-fade) no-ops
    /// instead of landing a stale alpha.
    private var fadeGenerations: [ObjectIdentifier: Int] = [:]

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

    /// Fades the window to an alpha, delivering `completion` once the value has
    /// arrived. The animation is not trusted to finish: in a session whose window
    /// animations have stopped running (measured after one display rearrangement
    /// — animator alpha changes never progressed, in this app and in a bare probe
    /// alike, while direct alpha sets worked), the delayed block lands the value
    /// itself. It is also the only deliverer of the completion — a completion
    /// handed to the animation group is retained forever by a group that never
    /// finishes, holding the window with it — and the generation counter retires
    /// a block whose fade a later re-show or dismissal has superseded. The block
    /// keeps the window alive until it has delivered.
    private func fade(_ window: NSWindow, to alpha: CGFloat, completion: (() -> Void)? = nil) {
        let key = ObjectIdentifier(window)
        let generation = (fadeGenerations[key] ?? 0) + 1
        fadeGenerations[key] = generation
        if window.alphaValue != alpha {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fadeDuration
                window.animator().alphaValue = alpha
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self = self, self.fadeGenerations[key] == generation else { return }
                self.fadeGenerations.removeValue(forKey: key)
                if window.alphaValue != alpha { window.alphaValue = alpha }
                completion?()
            }
        }
    }

    private func dismiss() {
        let dismissing = windows
        windows = []
        shownSize = .zero
        shownFrames = []
        for window in dismissing {
            fade(window, to: 0, completion: { window.orderOut(nil) })
        }
    }
}

/// Metrics shared by the OSDs so their pills read as one family: GNOME's
/// workspace-switcher slot and padding give every pill the same height and
/// padding, and one fade duration drives every show and hide.
enum OSDMetrics {
    static let slot: CGFloat = 32
    static let paddingX: CGFloat = 18
    static let paddingY: CGFloat = 12
    static let fadeDuration: TimeInterval = 0.2
}
