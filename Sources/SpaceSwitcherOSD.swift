import Cocoa

/// GNOME's workspace switcher popup: a pill holding one dot per space, the current
/// one filled in and larger.
///
/// The sizes are gnome-shell's, from `widgets/_workspace-switcher.scss`: each dot sits
/// in a 32pt slot, slots are 12pt apart, the panel is padded 12pt by 18pt, the active
/// dot is a third of a slot across and the inactive ones a sixth, drawn at half
/// opacity. The timings are from `workspaceSwitcherPopup.js`.
@MainActor
final class SpaceSwitcherOSD {
    private static let slot: CGFloat = 32
    private static let spacing: CGFloat = 12
    private static let paddingX: CGFloat = 18
    private static let paddingY: CGFloat = 12
    private static let activeDot: CGFloat = slot / 3
    private static let inactiveDot: CGFloat = slot / 6

    /// gnome-shell's own timings, from `workspaceSwitcherPopup.js`.
    private let panel = OSDPanel(displayDuration: 0.6, fadeDuration: 0.1)

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
            width: count * slot + max(count - 1, 0) * spacing + paddingX * 2,
            height: slot + paddingY * 2)
    }

    private static func layoutDots(in container: NSView, count: Int, activeIndex: Int) {
        container.subviews.forEach { $0.removeFromSuperview() }
        for index in 0..<count {
            let isActive = index == activeIndex
            let diameter = isActive ? activeDot : inactiveDot
            let slotOrigin = paddingX + CGFloat(index) * (slot + spacing)
            let dot = NSView(frame: NSRect(
                x: slotOrigin + (slot - diameter) / 2,
                y: paddingY + (slot - diameter) / 2,
                width: diameter, height: diameter))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = diameter / 2
            dot.layer?.backgroundColor = NSColor.white.withAlphaComponent(
                isActive ? 1 : 0.5).cgColor
            container.addSubview(dot)
        }
    }
}
