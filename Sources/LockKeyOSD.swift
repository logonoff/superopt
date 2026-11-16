import Cocoa

/// Caps Lock on-screen display, after gnome-shell-extension-lockkeys: a pill saying
/// which way the key just went, dimmed when it went off.
@MainActor
class LockKeyOSD {
    /// gnome-shell's OSD heading: 700 weight at 11pt, which is ~15pt measured in the
    /// macOS points the rest of the pill uses.
    private static let font = NSFont.systemFont(ofSize: 15, weight: .bold)
    private static let iconSize = OSDMetrics.slot
    /// Ink width of the ⇪ glyph at slot size, so margins measure to its drawn edge.
    private static let glyphInkWidth: CGFloat = {
        let attr = NSAttributedString(string: "⇪", attributes: [
            .font: NSFont.systemFont(ofSize: OSDMetrics.slot, weight: .bold)
        ])
        let line = CTLineCreateWithAttributedString(attr)
        guard let ctx = CGContext(
            data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return OSDMetrics.slot }
        return CTLineGetImageBounds(line, ctx).width
    }()

    private let panel = OSDPanel(displayDuration: 1.5, fadeDuration: OSDMetrics.fadeDuration)

    func show(text: String, active: Bool) {
        panel.show(size: Self.size(for: text), on: NSScreen.screens, announcement: text) { view in
            Self.layout(in: view, label: text, active: active)
        }
    }

    private static func size(for text: String) -> NSSize {
        let glyph = ceil(glyphInkWidth)
        let textWidth = ceil(textSize(of: text).width)
        // The icon-to-text gap is half the side padding, so it reads as tighter than
        // the pill's inner margins rather than another full one.
        let gap = OSDMetrics.paddingX / 2
        return NSSize(
            width: OSDMetrics.paddingX + glyph + gap + textWidth + OSDMetrics.paddingX,
            height: iconSize + OSDMetrics.paddingY * 2)
    }

    private static func layout(in view: NSView, label: String, active: Bool) {
        let icon = view.subviews.compactMap { $0 as? CapsLockIconView }.first ?? addIcon(to: view)
        let field = view.subviews.compactMap { $0 as? NSTextField }.first ?? addLabel(to: view)
        icon.active = active
        field.stringValue = label
        field.baseWritingDirection = localizationWritingDirection

        let textSize = textSize(of: label)
        let glyph = ceil(glyphInkWidth)
        let gap = OSDMetrics.paddingX / 2
        icon.frame = NSRect(
            x: OSDMetrics.paddingX, y: OSDMetrics.paddingY,
            width: glyph, height: iconSize)
        field.frame = NSRect(
            x: OSDMetrics.paddingX + glyph + gap,
            y: (view.bounds.height - textSize.height) / 2,
            width: ceil(textSize.width), height: ceil(textSize.height))
    }

    /// Measured through a real field: NSTextField wants a few points more than the
    /// raw attributed string, and sizing from the string alone clipped the last word.
    private static let measureField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.font = font
        return field
    }()

    private static func textSize(of text: String) -> NSSize {
        measureField.stringValue = text
        measureField.sizeToFit()
        return measureField.frame.size
    }

    private static func addIcon(to view: NSView) -> CapsLockIconView {
        let icon = CapsLockIconView(frame: .zero)
        view.addSubview(icon)
        return icon
    }

    /// The base writing direction of the localization the app is running in.
    /// The label starts with Latin text (⇪ Caps Lock), so leaving the field on
    /// `.natural` lets the first-strong-character heuristic pick left-to-right
    /// and an Arabic status word reads before the key name instead of after it.
    private static let localizationWritingDirection: NSWritingDirection = {
        guard let language = Bundle.main.preferredLocalizations.first else { return .leftToRight }
        return NSParagraphStyle.defaultWritingDirection(forLanguage: language)
    }()

    private static func addLabel(to view: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        view.addSubview(label)
        return label
    }
}

/// The ⇪ Caps Lock glyph. Ink-centered: the glyph sits high in its line box, so centering on
/// the advance would leave it floating near the top of the slot.
private final class CapsLockIconView: NSView {
    var active = true {
        didSet {
            if active != oldValue { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let attr = NSAttributedString(string: "⇪", attributes: [
            .font: NSFont.systemFont(ofSize: OSDMetrics.slot, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(active ? 1 : 0.35)
        ])
        let line = CTLineCreateWithAttributedString(attr)
        let ink = CTLineGetImageBounds(line, ctx)
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX - ink.midX, y: bounds.midY - ink.midY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
