import Cocoa
import SwiftUI

/// One pane of the settings window: one sidebar row and one detail form.
/// The raw value is the identity used for selection.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case desktop
    case keyboard
    case input
    case shortcutRemapping
    case excludedApps

    var id: String { rawValue }

    /// The localization key, shared with the section headers this pane replaced.
    var titleKey: String {
        switch self {
        case .desktop:
            return "Desktop"
        case .keyboard:
            return "Keyboard"
        case .input:
            return "Input"
        case .shortcutRemapping:
            return "Shortcut Remapping"
        case .excludedApps:
            return "Excluded Apps"
        }
    }

    var title: String {
        NSLocalizedString(titleKey, comment: "Settings pane title")
    }

    /// SF Symbol drawn in white on the sidebar glyph.
    var symbol: String {
        switch self {
        case .desktop:
            return "desktopcomputer"
        case .keyboard:
            return "keyboard"
        case .input:
            return "option"
        case .shortcutRemapping:
            return "command"
        case .excludedApps:
            return "hand.raised"
        }
    }

    /// Gradient stops for the sidebar glyph, top to bottom.
    var iconColors: [Color] {
        switch self {
        case .desktop:
            return [Color(red: 0.42, green: 0.72, blue: 1), Color(red: 0.05, green: 0.38, blue: 0.95)]
        case .keyboard:
            return [Color(red: 0.62, green: 0.64, blue: 0.67), Color(red: 0.33, green: 0.35, blue: 0.38)]
        case .input:
            return [Color(red: 0.82, green: 0.55, blue: 1), Color(red: 0.48, green: 0.34, blue: 0.95)]
        case .shortcutRemapping:
            return [Color(red: 1, green: 0.75, blue: 0.25), Color(red: 0.95, green: 0.44, blue: 0.1)]
        case .excludedApps:
            return [Color(red: 0.6, green: 0.6, blue: 1), Color(red: 0.32, green: 0.32, blue: 0.9)]
        }
    }

    /// Optical centering correction for the symbol, measured against the
    /// rendered icon squares (not the AX frames, which sit ~1 pt off the
    /// visual square): each value cancels the measured offset of the glyph's
    /// bounding box within its square.
    var iconCorrection: CGSize {
        switch self {
        case .desktop:
            return CGSize(width: 0.0, height: -0.4)
        case .keyboard:
            return CGSize(width: 0.4, height: -0.2)
        case .input:
            return CGSize(width: 0.0, height: 0.4)
        case .shortcutRemapping:
            return CGSize(width: 0.9, height: -0.9)
        case .excludedApps:
            return CGSize(width: 0.9, height: -0.1)
        }
    }
}

/// The colored rounded-square glyph beside each sidebar row, like the pane
/// icons in System Settings. Follows the system's icon appearance with the
/// six variants measured from the real app's sidebar: light regular is the
/// full-colour gradient with a white glyph; dark regular is a near-black
/// background with the glyph in the icon's own colours; clear is flat gray
/// (mid gray in light, darker in dark) with a white glyph; tinted is the tint
/// colour (light) or the tint over a dark base (dark) with a tinted glyph.
struct SettingsPaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        let mode = IconAppearance.shared.mode
        let tint = IconAppearance.shared.tintColor
        let gradient = LinearGradient(
            colors: pane.iconColors, startPoint: .top, endPoint: .bottom)

        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Self.background(mode: mode, gradient: gradient, tint: tint))
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: pane.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Self.glyph(mode: mode, gradient: gradient, tint: tint))
                    .offset(pane.iconCorrection)
            }
    }

    private static func background(
        mode: IconAppearance.Mode, gradient: LinearGradient, tint: Color
    ) -> AnyShapeStyle {
        switch mode {
        case .regularLight:
            return AnyShapeStyle(gradient)
        case .regularDark:
            return AnyShapeStyle(Color(red: 0.115, green: 0.115, blue: 0.118))
        case .clearLight:
            return AnyShapeStyle(Color(white: 0.49))
        case .clearDark:
            return AnyShapeStyle(Color(white: 0.17))
        case .tintedLight:
            return AnyShapeStyle(tint)
        case .tintedDark:
            // The tint at ~18% over a dark base, measured (22,41,57) for blue.
            return AnyShapeStyle(blend(tint, with: Color(white: 0.086), at: 0.18))
        }
    }

    private static func glyph(
        mode: IconAppearance.Mode, gradient: LinearGradient, tint: Color
    ) -> AnyShapeStyle {
        switch mode {
        case .regularLight, .clearLight, .clearDark:
            return AnyShapeStyle(Color.white)
        case .regularDark:
            return AnyShapeStyle(gradient)
        case .tintedLight:
            // Half white, half tint — measured (124,188,215) for blue.
            return AnyShapeStyle(blend(Color.white, with: tint, at: 0.5))
        case .tintedDark:
            return AnyShapeStyle(tint)
        }
    }

    /// Linear blend of two colours, `amount` being the weight of the first.
    private static func blend(_ first: Color, with second: Color, at amount: Double) -> Color {
        let firstComponents = NSColor(first).usingColorSpace(.deviceRGB)
        let secondComponents = NSColor(second).usingColorSpace(.deviceRGB)
        guard let firstComponents, let secondComponents else { return first }
        return Color(
            red: firstComponents.redComponent * amount + secondComponents.redComponent * (1 - amount),
            green: firstComponents.greenComponent * amount + secondComponents.greenComponent * (1 - amount),
            blue: firstComponents.blueComponent * amount + secondComponents.blueComponent * (1 - amount))
    }
}

/// The settings window, laid out like System Settings: a sidebar of panes with
/// colored glyphs, and a detail column with the selected pane's form. The
/// pane's name is the window title, drawn in the toolbar.
struct SettingsView: View {
    // System Settings reopens on the pane that was last shown; so does this.
    @AppStorage("settingsSelectedPane") private var selection: SettingsPane = .desktop

    /// The list takes an optional selection so the detail pane follows clicks.
    private var listSelection: Binding<SettingsPane?> {
        Binding(
            get: { selection },
            set: { if let pane = $0 { selection = pane } }
        )
    }

    var body: some View {
        // System Settings' shell, as its binary shows it: the plain two-column
        // split view with the sidebar toggle removed from the toolbar and the
        // pane name as the window title. The transparent title bar with the
        // traffic lights over the sidebar comes with the split view itself.
        NavigationSplitView {
            SettingsSidebar(selection: listSelection)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(232)
        } detail: {
            // The detail column is a NavigationStack, as in System Settings —
            // it is what integrates the scrolling form with the toolbar's
            // scroll-edge effect (the translucent strip that replaces the
            // toolbar's fill when a pane is scrolled).
            NavigationStack {
                SettingsDetail(pane: selection)
                    // The Form's default 20 pt top content margin puts the first
                    // card at y=72; the real app's cards start at y=64 (12 pt
                    // below the toolbar — measured, not half of our 20). Cancel
                    // the extra 8 pt. The scroll area extends under the toolbar
                    // by the same 8 pt, which the scroll-edge effect covers.
                    .contentMargins(.top, -8, for: .scrollContent)
                    // The pane's name as the window title, rendered by the
                    // system in the toolbar after the leading spacer — plain
                    // text with no glass capsule, the way System Settings
                    // names its panes. The spacer keeps the toolbar alive and
                    // the title at the leading edge of the detail column.
                    .navigationTitle(selection.title)
                    .toolbar {
                        ToolbarSpacer(.fixed, placement: .navigation)
                    }
            }
        }
        // The hosting view drives the window's min/max sizes from these
        // constraints (they override any NSWindow minSize/maxSize). A fixed
        // width here is what makes the window vertical-only resizable:
        // AppKit reads the matching min/max width and drops the horizontal
        // resize cursor from the side edges. The panes vary in height, so the
        // height keeps a floor and no ceiling.
        .frame(minWidth: 740, idealWidth: 740, maxWidth: 740, minHeight: 420)
        .onAppear {
            IconAppearance.shared.start()
        }
        .onDisappear {
            IconAppearance.shared.stop()
        }
    }
}

/// The sidebar column: the selectable pane list.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                SidebarRow(pane: pane)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
    }
}

/// One pane in the sidebar list: colored glyph and title.
private struct SidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 8) {
            SettingsPaneIcon(pane: pane)
            title
        }
        // 32 pt row pitch with 24 pt of content, matching System Settings'
        // sidebar rows; the List's own row inset puts the glyph at the same
        // offset from the window edge as the real app's.
        .frame(minHeight: 24, alignment: .leading)
    }

    /// Literal Text() calls per case so genstrings keeps extracting the pane
    /// titles, which also name the window.
    @ViewBuilder
    private var title: some View {
        switch pane {
        case .desktop:
            Text("Desktop")
        case .keyboard:
            Text("Keyboard")
        case .input:
            Text("Input")
        case .shortcutRemapping:
            Text("Shortcut Remapping")
        case .excludedApps:
            Text("Excluded Apps")
        }
    }
}

/// The detail column: just the pane's form. As in System Settings, the pane has
/// no large title of its own — the column starts below the title bar and the
/// pane's name is the window title.
private struct SettingsDetail: View {
    let pane: SettingsPane

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .desktop:
            DesktopPane()
        case .keyboard:
            KeyboardPane()
        case .input:
            InputPane()
        case .shortcutRemapping:
            ShortcutRemappingPane()
        case .excludedApps:
            ExcludedAppsPane()
        }
    }
}

@MainActor
class SettingsWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("superopt-settings")

    /// The window's width never changes; only the height is resizable.
    static let fixedWidth: CGFloat = 740

    private var window: NSWindow?

    func show() {
        if let existing = window {
            activateAndFront(existing)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())

        // A standard titled window with a toolbar, as in System Settings:
        // fullSizeContentView lets the split view run the full height so the
        // sidebar's material shows through the toolbar's sidebar region and
        // SwiftUI draws its tracking separator at the seam. Fixed width
        // (740 pt, the width System Settings opens at); the panes vary in
        // height, so the height stays resizable.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.fixedWidth, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Settings", comment: "Settings window title")
        window.identifier = Self.windowIdentifier
        window.setFrame(
            NSRect(x: 0, y: 0, width: Self.fixedWidth, height: 684), display: false)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hostingView

        activateAndFront(window)
        self.window = window
    }

    // Plain activate() is cooperative and never activates this accessory app while
    // another app is frontmost, leaving the window behind it (measured on macOS 27).
    // The deprecated activate(ignoringOtherApps:) is the only variant that works.
    private func activateAndFront(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
