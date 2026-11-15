import Cocoa

/// A workspace switcher popup: a pill holding one dot per space, the current
/// one filled in and larger.
@MainActor
final class SpaceSwitcherOSD {
    private static let spacing: CGFloat = 12
    private static let activeDot: CGFloat = OSDMetrics.slot / 3
    private static let inactiveDot: CGFloat = OSDMetrics.slot / 6

    private let panel = OSDPanel(displayDuration: 0.6, fadeDuration: OSDMetrics.fadeDuration)

    func show(spaceCount: Int, activeIndex: Int, on screens: [NSScreen]) {
        guard spaceCount > 0 else { return }
        let announcement = String(
            format: NSLocalizedString("Desktop %1$d of %2$d",
                                      comment: "Spoken when the space changes"),
            activeIndex + 1, spaceCount)

        panel.show(size: Self.size(spaceCount: spaceCount), on: screens,
                   announcement: announcement) { view in
            Self.layoutDots(in: view, count: spaceCount, activeIndex: activeIndex)
        }
    }

    private static func size(spaceCount: Int) -> NSSize {
        let count = CGFloat(spaceCount)
        return NSSize(
            width: count * OSDMetrics.slot + max(count - 1, 0) * spacing + OSDMetrics.paddingX * 2,
            height: OSDMetrics.slot + OSDMetrics.paddingY * 2)
    }

    private static func layoutDots(in container: NSView, count: Int, activeIndex: Int) {
        container.subviews.forEach { $0.removeFromSuperview() }
        for index in 0..<count {
            let isActive = index == activeIndex
            let diameter = isActive ? activeDot : inactiveDot
            let slotOrigin = OSDMetrics.paddingX + CGFloat(index) * (OSDMetrics.slot + spacing)
            let dot = NSView(frame: NSRect(
                x: slotOrigin + (OSDMetrics.slot - diameter) / 2,
                y: OSDMetrics.paddingY + (OSDMetrics.slot - diameter) / 2,
                width: diameter, height: diameter))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = diameter / 2
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(
                isActive ? 1 : 0.5).cgColor
            container.addSubview(dot)
        }
    }
}
