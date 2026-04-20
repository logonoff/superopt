import Cocoa
import QuartzCore

class LockKeyOSD {
    private var windows: [NSWindow] = []
    private var dismissWorkItem: DispatchWorkItem?

    private let displayDuration: TimeInterval = 1.5
    private let fadeDuration: TimeInterval = 0.2
    private let osdWidth: CGFloat = 220
    private let osdHeight: CGFloat = 80

    func show(text: String, active: Bool) {
        dismissWorkItem?.cancel()

        let textAlpha: CGFloat = active ? 1.0 : 0.4

        if windows.isEmpty {
            createWindows(text: text, textAlpha: textAlpha)
        } else {
            for window in windows {
                if let glass = window.contentView as? NSGlassEffectView,
                   let label = glass.contentView?.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
                    label.stringValue = text
                    label.alphaValue = textAlpha
                }
                window.alphaValue = 1
            }
        }

        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text])

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: work)
    }

    private func createWindows(text: String, textAlpha: CGFloat) {
        for screen in NSScreen.screens {
            let window = createWindow(text: text, textAlpha: textAlpha, on: screen)
            windows.append(window)
        }
    }

    private func createWindow(text: String, textAlpha: CGFloat, on screen: NSScreen) -> NSWindow {
        let originX = screen.frame.midX - osdWidth / 2
        let originY = screen.frame.minY + screen.frame.height * 0.12

        let window = NSWindow(
            contentRect: NSRect(x: originX, y: originY, width: osdWidth, height: osdHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.alphaValue = textAlpha
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentWrapper = NSView(frame: NSRect(x: 0, y: 0, width: osdWidth, height: osdHeight))
        contentWrapper.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentWrapper.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentWrapper.centerYAnchor)
        ])

        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: osdWidth, height: osdHeight))
        if let clearStyle = NSGlassEffectView.Style(rawValue: 1) {
            glass.style = clearStyle
        }
        glass.cornerRadius = 9999
        glass.contentView = contentWrapper

        window.contentView = glass
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fadeDuration
            window.animator().alphaValue = 1
        }

        return window
    }

    private func dismiss() {
        let windowsToRemove = windows
        windows = []

        for window in windowsToRemove {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = fadeDuration
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
            })
        }
    }
}
