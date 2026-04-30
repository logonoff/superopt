import Cocoa

class HoverButton: NSButton {
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self)
        hoverTrackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        layer?.cornerRadius = 6
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }
}
