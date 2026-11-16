import AppKit
import SwiftUI

/// One node of the shortcut tree: a category, or a shortcut inside one.
/// `children` is what makes the tree hierarchical for the outline view's
/// data source. A class, not a struct: NSOutlineView identifies items by
/// identity, and struct copies would defeat `row(forItem:)` lookups (and
/// with them the row refresh after a checkbox toggle — measured: the
/// refresh silently no-ops when the item is a value copy).
final class ShortcutNode: Identifiable {
    let id: String
    let label: String
    /// The shortcut's remapped keys, trailing; nil on category rows.
    let keys: String?
    /// The category's hint, shown as a tooltip; nil on shortcut rows.
    let hint: String?
    var children: [ShortcutNode]?

    init(id: String, label: String, keys: String?, hint: String?, children: [ShortcutNode]?) {
        self.id = id
        self.label = label
        self.keys = keys
        self.hint = hint
        self.children = children
    }

    /// The whole tree: every category with its shortcuts under it.
    @MainActor static let tree: [ShortcutNode] = GnomeShortcutHandler.categories.map { category in
        ShortcutNode(
            id: "category:\(category)",
            label: category,
            keys: nil,
            hint: categoryHints[category],
            children: GnomeShortcutHandler.shortcuts(in: category).map { shortcut in
                ShortcutNode(
                    id: shortcut.id,
                    label: shortcut.label,
                    // Verbatim: the key combos are data, not localizable text.
                    keys: "\(shortcut.fromKeys) ▸ \(shortcut.toKeys)",
                    hint: nil,
                    children: nil
                )
            }
        )
    }

    /// Category hints for tooltips — the tree's rows are single-line, so
    /// the qualifier lives on hover.
    private static let categoryHints: [String: String] = [
        NSLocalizedString("General", comment: "Shortcut category"):
            NSLocalizedString("Copy, Paste, Undo, Find, and other essentials", comment: "Category hint"),
        NSLocalizedString("File", comment: "Shortcut category"):
            NSLocalizedString("New, Save, Print, and Quit", comment: "Category hint"),
        NSLocalizedString("View", comment: "Shortcut category"):
            NSLocalizedString("Zoom and full screen", comment: "Category hint"),
        NSLocalizedString("Text Editing", comment: "Shortcut category"):
            NSLocalizedString("Word-level navigation, deletion, and formatting", comment: "Category hint"),
        NSLocalizedString("Finder", comment: "Shortcut category"):
            NSLocalizedString("Active only in the Finder", comment: "Category hint"),
        NSLocalizedString("Tabs & Windows", comment: "Shortcut category"):
            NSLocalizedString("Tab and window management", comment: "Category hint"),
        NSLocalizedString("Browsers", comment: "Shortcut category"):
            NSLocalizedString("Active only in browsers", comment: "Category hint"),
        NSLocalizedString("Terminal", comment: "Shortcut category"):
            NSLocalizedString("Active only in terminal apps", comment: "Category hint"),
        NSLocalizedString("Code Editors", comment: "Shortcut category"):
            NSLocalizedString("Active only in code editors", comment: "Category hint")
    ]
}

/// The shortcut tree as a real NSOutlineView wrapped for SwiftUI.
/// A SwiftUI `List(children:)` is also NSOutlineView-backed,
/// but below a Form its row background layer never draws (measured: the
/// system alternation comes out in multi-row blocks regardless of
/// listRowBackground), so the tree is bridged directly instead: the
/// outline view gives the bordered scrolling area, alternating 24 pt rows,
/// disclosure triangles, per-level indentation, and native mixed-state
/// checkboxes, none of it hand-rolled.
struct ShortcutOutline: NSViewRepresentable {
    var settings: GnomeShortcutSettings

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.rowHeight = 24
        outline.usesAlternatingRowBackgroundColors = true
        outline.indentationPerLevel = 13
        // .plain, not the default .automatic: automatic resolves to a
        // slightly tighter leading inset here and draws the disclosure
        // triangle 10 pt further in. With .plain a row's content starts
        // 26 pt from the outline's leading edge at the top level and 39 pt
        // one level in, which is where an AppKit outline of checkbox rows
        // belongs.
        outline.style = .plain
        outline.headerView = nil
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let column = NSTableColumn(identifier: Self.columnIdentifier)
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.sizeLastColumnToFit()
        context.coordinator.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // The tree's data is static; checkbox state is read from settings
        // when a row view is configured and written straight back through
        // the coordinator, so there is nothing to push in.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    private static let columnIdentifier = NSUserInterfaceItemIdentifier("shortcut")
    private static let rowIdentifier = NSUserInterfaceItemIdentifier("row")

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        private let settings: GnomeShortcutSettings
        weak var outline: NSOutlineView?

        init(settings: GnomeShortcutSettings) {
            self.settings = settings
        }

        // MARK: - Data source

        func outlineView(
            _ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?
        ) -> Int {
            if let node = item as? ShortcutNode {
                return node.children?.count ?? 0
            }
            return ShortcutNode.tree.count
        }

        func outlineView(
            _ outlineView: NSOutlineView, child index: Int, ofItem item: Any?
        ) -> Any {
            if let node = item as? ShortcutNode, let children = node.children {
                return children[index]
            }
            return ShortcutNode.tree[index]
        }

        func outlineView(
            _ outlineView: NSOutlineView, isItemExpandable item: Any
        ) -> Bool {
            (item as? ShortcutNode)?.children != nil
        }

        // MARK: - Delegate

        func outlineView(
            _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
        ) -> NSView? {
            guard let node = item as? ShortcutNode else { return nil }
            let view = outlineView.makeView(
                withIdentifier: ShortcutOutline.rowIdentifier, owner: nil
            ) as? ShortcutOutlineRowView ?? ShortcutOutlineRowView()
            view.identifier = ShortcutOutline.rowIdentifier
            view.configure(node: node, target: self)
            return view
        }

        // MARK: - Checkbox actions

        /// `NSTableView.row(for:)` maps the clicked checkbox back to its row,
        /// so the button carries no state of its own.
        @objc func toggle(_ sender: NSButton) {
            guard let outline else { return }
            let row = outline.row(for: sender)
            guard row >= 0, let node = outline.item(atRow: row) as? ShortcutNode else { return }
            if node.children != nil {
                // Tri-state semantics: off turns on, anything else turns off.
                let nextOn = settings.categoryState(node.label) == .allOff
                settings.setCategoryEnabled(node.label, nextOn)
                for child in node.children ?? [] {
                    refresh(child)
                }
                refresh(node)
            } else {
                settings.setEnabled(node.id, sender.state == .on)
                refresh(node)
                if let parent = parent(of: node) {
                    refresh(parent)
                }
            }
        }

        /// Reconfigures a row's view from the model. The clicked button
        /// cycles its own state (a mixed-state checkbox cycles off → mixed
        /// → on) before the action runs, and `reloadItem` does not re-ask
        /// the delegate for a visible row's view, so the authoritative
        /// state has to be written back through the row view itself.
        private func refresh(_ node: ShortcutNode) {
            guard let outline else { return }
            let row = outline.row(forItem: node)
            guard row >= 0,
                  let rowView = outline.rowView(atRow: row, makeIfNecessary: false),
                  let cell = rowView.view(atColumn: 0) as? ShortcutOutlineRowView
            else { return }
            cell.configure(node: node, target: self)
        }

        private func parent(of node: ShortcutNode) -> ShortcutNode? {
            outline?.parent(forItem: node) as? ShortcutNode
        }

        func state(of node: ShortcutNode) -> NSControl.StateValue {
            if node.children != nil {
                switch settings.categoryState(node.label) {
                case .allOn: return .on
                case .allOff: return .off
                case .mixed: return .mixed
                }
            }
            return settings.isEnabled(node.id) ? .on : .off
        }
    }
}

/// One row of the tree: checkbox and label leading, the remapped keys
/// trailing in the row's normal text color. The outline view positions the
/// row view after the disclosure triangle and the item's indentation; the
/// shortcut rows' extra inset comes from being one level deeper.
///
/// Leading/trailing anchors, so the row mirrors itself in a right-to-left
/// localization (the app ships Arabic); an `NSTableCellView`, so the cell
/// forwards its `backgroundStyle` to `textField` and the label inverts with
/// the row when it is selected.
@MainActor
final class ShortcutOutlineRowView: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let keys = NSTextField(labelWithString: "")
    /// The key-combo field's width, set from its content in `configure`.
    private let keysWidth: NSLayoutConstraint

    init() {
        keysWidth = keys.widthAnchor.constraint(equalToConstant: 0)
        super.init(frame: .zero)

        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        // NSTableCellView pushes backgroundStyle into this field, which is
        // what inverts the label's color on a selected row.
        textField = label

        for view in [checkbox, label, keys] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // The label gives up width first; the key combos are never truncated.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        keys.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The checkbox sits flush at the row's leading edge, its label
        // 15 pt past the checkbox's trailing edge. The constant below is 17
        // rather than 15 because Auto Layout measures from the checkbox's
        // alignment rect, which is 2 pt narrower than its frame (measured:
        // 17 puts the label exactly 15 pt from the frame).
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 17),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            keys.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            // Clear of the overlay scroller, which floats over the row's
            // trailing ~11 pt when the tree scrolls.
            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            keys.centerYAnchor.constraint(equalTo: centerYAnchor),
            keysWidth
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(node: ShortcutNode, target: ShortcutOutline.Coordinator) {
        checkbox.allowsMixedState = node.children != nil
        checkbox.state = target.state(of: node)
        checkbox.target = target
        checkbox.action = #selector(ShortcutOutline.Coordinator.toggle(_:))
        // The checkbox has no title of its own, so name it for VoiceOver.
        checkbox.setAccessibilityLabel(node.label)
        textField?.stringValue = node.label
        keys.stringValue = node.keys ?? ""
        keys.isHidden = node.keys == nil
        // A little wider than the intrinsic size: symbol-heavy strings
        // (⌘, ▸) measure a pixel or two narrower than they render, and a
        // field sized exactly clips its last glyph.
        keysWidth.constant = node.keys == nil ? 0 : ceil(keys.intrinsicContentSize.width) + 4
        toolTip = node.hint
    }
}
