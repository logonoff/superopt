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

    /// Where one status string's glyphs land: the field's own content size, the
    /// ink box within that frame, and how far the text's visual mass (its
    /// alpha-weighted centroid) sits above that box's center — negative when it
    /// sits below. An NSTextField cell draws its text a few points inside its
    /// frame — ≈5pt on the left, and the ink center ≈1pt below the frame center —
    /// so the frame is not where the text is. Laying out by frame left the label
    /// sitting low beside the ink-centered icon and widened the icon-to-text gap
    /// by the cell's left inset. Measured per string by rasterizing, because the
    /// insets come from the cell and vary with the string's glyphs.
    private struct LabelGeometry {
        let fieldSize: NSSize
        let inkRect: NSRect
        let centroidRise: CGFloat
    }

    private static var labelGeometryCache: [String: LabelGeometry] = [:]

    /// How far the ⇪ glyph's visual mass sits below its ink box center: the glyph
    /// is a hollow arrowhead over a solid box, so its weight is bottom-heavy and
    /// a bounding-box-centered glyph reads shifted down next to the text.
    /// Measured once at launch; see `measureGlyphOptics`.
    private static var glyphCentroidDrop: CGFloat = 0

    /// Rasterizes the status strings' ink boxes once, before the event tap
    /// exists. The tap callback must return quickly — a slow one gets the tap
    /// disabled by timeout — so it does no drawing, and measuring at launch
    /// costs nothing per show.
    func prepare(texts: [String]) {
        Self.measureGlyphOptics()
        for text in texts {
            let field = Self.measureField(for: text)
            let measured = Self.rasterizedGeometry(of: field)
            Self.labelGeometryCache[text] = LabelGeometry(
                fieldSize: field.frame.size,
                inkRect: measured?.inkRect ?? NSRect(origin: .zero, size: field.frame.size),
                centroidRise: measured?.centroidRise ?? 0)
        }
    }

    /// The geometry for one string: the rasterized ink box when `prepare` covered
    /// it, otherwise a frame-sized fallback from layout math alone. Only the
    /// fallback can run on the event tap callback, and it draws nothing.
    private static func labelGeometry(for text: String) -> LabelGeometry {
        if let cached = labelGeometryCache[text] { return cached }
        let fieldSize = measureField(for: text).frame.size
        return LabelGeometry(fieldSize: fieldSize,
                             inkRect: NSRect(origin: .zero, size: fieldSize),
                             centroidRise: 0)
    }

    /// A label field sized to the string. `sizeToFit` is layout math with no
    /// drawing, safe on any path.
    private static func measureField(for text: String) -> NSTextField {
        let field = makeLabel()
        field.stringValue = text
        field.sizeToFit()
        return field
    }

    /// The glyph's centroid drop, rendered through an offline context and scanned
    /// — the same measured-not-assumed rule as everything else in this file.
    private static func measureGlyphOptics() {
        let canvas = OSDMetrics.slot * 2
        let view = CapsLockIconView(frame: NSRect(
            origin: .zero, size: NSSize(width: canvas, height: canvas)))
        let scale: CGFloat = 2
        let pixels = Int(canvas * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: canvas, height: canvas)
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let scanned = scan(rep) else { return }
        // The scan's rise is positive above the ink center; the drop is the
        // glyph's mass below it.
        glyphCentroidDrop = -scanned.centroidRise
    }

    /// The field's ink box and centroid rise, in its own coordinates, rasterized
    /// at 2x so the box lands on half-point boundaries rather than whole pixels.
    /// Called only from `prepare`, at launch — never from the event tap callback,
    /// which must not draw.
    private static func rasterizedGeometry(of field: NSTextField) -> (inkRect: NSRect, centroidRise: CGFloat)? {
        let bounds = field.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale: CGFloat = 2
        let width = Int(ceil(bounds.width * scale)), height = Int(ceil(bounds.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        field.cacheDisplay(in: bounds, to: rep)
        return scan(rep)
    }

    /// The ink box (in the rep's point coordinates, bottom-up) and the centroid's
    /// rise above the box center, from a rendered bitmap. Top-down rows: a
    /// centroid above the box center is a smaller row number.
    private static func scan(
        _ rep: NSBitmapImageRep
    ) -> (inkRect: NSRect, centroidRise: CGFloat)? {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        let boundsHeight = rep.size.height
        // Points per pixel, derived from the rep itself: the pixel counts are
        // ceiled, so assuming a round scale would skew the mapping by up to half
        // a point at the far edge.
        let pointX = rep.size.width / CGFloat(width)
        let pointY = boundsHeight / CGFloat(height)
        var minX = CGFloat.greatestFiniteMagnitude, maxX: CGFloat = -1
        var minY = CGFloat.greatestFiniteMagnitude, maxY: CGFloat = -1
        var weightSum = 0.0, weightedRow = 0.0
        for row in 0..<height {
            for column in 0..<width {
                guard let alpha = rep.colorAt(x: column, y: row)?.alphaComponent, alpha > 0.1 else { continue }
                let inkX = CGFloat(column) * pointX
                let inkY = boundsHeight - CGFloat(row) * pointY
                minX = min(minX, inkX); maxX = max(maxX, inkX)
                minY = min(minY, inkY); maxY = max(maxY, inkY)
                weightSum += Double(alpha)
                weightedRow += Double(alpha) * Double(row)
            }
        }
        guard maxX >= 0, maxY >= 0, weightSum > 0 else { return nil }
        // Rows are top-down: convert the centroid to the ink box's bottom-up
        // points before comparing it to the box center.
        let centroidY = boundsHeight - CGFloat(weightedRow / weightSum) * pointY
        let centroidRise = centroidY - (minY + maxY) / 2
        return (NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), centroidRise)
    }

    private static func size(for text: String) -> NSSize {
        let geometry = labelGeometry(for: text)
        let glyph = ceil(glyphInkWidth)
        let textWidth = ceil(geometry.inkRect.width)
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

        let geometry = labelGeometry(for: label)
        let glyph = ceil(glyphInkWidth)
        let gap = OSDMetrics.paddingX / 2
        // Raise the icon so the glyph's visual mass sits on the text's: both are
        // placed by their ink boxes, but the glyph's weight is bottom-heavy while
        // the text's sits at (or slightly above) its box center, so a box-centered
        // glyph reads shifted down. Both parts are measured at launch — the
        // glyph's drop once, the string's rise per prepared string.
        let rise = glyphCentroidDrop + geometry.centroidRise
        icon.frame = NSRect(
            x: OSDMetrics.paddingX, y: OSDMetrics.paddingY + rise,
            width: glyph, height: iconSize)
        // Place the field by its ink — the rule the icon already follows: the text's
        // ink starts one gap past the icon's slot, and its ink center sits on the
        // pill's center line.
        let inkX = OSDMetrics.paddingX + glyph + gap
        field.frame = NSRect(
            x: inkX - geometry.inkRect.minX,
            y: view.bounds.midY - geometry.inkRect.midY,
            width: geometry.fieldSize.width, height: geometry.fieldSize.height)
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

    /// One label field, built the same way for measuring and for display, so the
    /// measured geometry is the geometry that renders.
    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.baseWritingDirection = localizationWritingDirection
        return label
    }

    private static func addLabel(to view: NSView) -> NSTextField {
        let label = makeLabel()
        view.addSubview(label)
        return label
    }
}

/// The ⇪ Caps Lock glyph. Ink-centered: the glyph sits high in its line box, so
/// centering on the advance would leave it floating near the top of the slot.
/// The view itself is raised by `LockKeyOSD.layout` to put the glyph's visual
/// mass on the text's optical line. Measured through itself at launch, so the
/// measured optics are the optics that render.
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
