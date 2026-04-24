import Cocoa

@MainActor
class CloseOverlay {
    let window: NSWindow
    private let buttonView: CloseButtonView

    init(origin: NSPoint, size: CGFloat, hovered: Bool) {
        let frame = NSRect(x: origin.x, y: origin.y, width: size, height: size)
        window = NSWindow(contentRect: frame, styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false; window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isReleasedWhenClosed = false; window.ignoresMouseEvents = true
        buttonView = CloseButtonView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        buttonView.isHovered = hovered
        window.contentView = buttonView; window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15; window.animator().alphaValue = 1
        }
    }

    func reposition(origin: NSPoint) { window.setFrameOrigin(origin) }

    func setState(hovered: Bool) {
        guard buttonView.isHovered != hovered else { return }
        buttonView.isHovered = hovered; buttonView.needsDisplay = true
    }

    func close() { window.close() }
}

private class CloseButtonView: NSView {
    var isHovered = false

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3,
                       color: NSColor(white: 0, alpha: 0.5).cgColor)
        ctx.addPath(CGPath(ellipseIn: rect, transform: nil))
        ctx.setFillColor(isHovered ? NSColor.systemRed.cgColor
                                   : CGColor(gray: 0.18, alpha: 0.9))
        ctx.fillPath()
        ctx.restoreGState()
        let xInset = rect.width * 0.3
        let xRect = rect.insetBy(dx: xInset, dy: xInset)
        let xPath = NSBezierPath()
        xPath.move(to: NSPoint(x: xRect.minX, y: xRect.minY))
        xPath.line(to: NSPoint(x: xRect.maxX, y: xRect.maxY))
        xPath.move(to: NSPoint(x: xRect.maxX, y: xRect.minY))
        xPath.line(to: NSPoint(x: xRect.minX, y: xRect.maxY))
        xPath.lineWidth = 1.5; xPath.lineCapStyle = .round
        NSColor.white.setStroke(); xPath.stroke()
    }
}
