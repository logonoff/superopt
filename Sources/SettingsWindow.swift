import Cocoa
import SwiftUI

/// Every pane shares this width, so switching panes never shifts the window
/// sideways.
private let settingsPaneWidth: CGFloat = 560

/// Where the selected pane is persisted between launches, so the window
/// reopens on the pane that was last shown.
private let settingsSelectedPaneKey = "settingsSelectedPane"

/// One pane of the settings window: one icon in the window's toolbar and one
/// form below it. The raw value is the identity used for selection.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case desktop
    case keyboard
    case input
    case excludedApps

    var id: String { rawValue }

    // Literal NSLocalizedString calls per case so genstrings extracts the
    // pane titles, which name the toolbar items and the window title.
    var title: String {
        switch self {
        case .desktop:
            return NSLocalizedString("Desktop", comment: "Settings pane title")
        case .keyboard:
            return NSLocalizedString("Keyboard", comment: "Settings pane title")
        case .input:
            return NSLocalizedString("Input", comment: "Settings pane title")
        case .excludedApps:
            return NSLocalizedString("Excluded Apps", comment: "Settings pane title")
        }
    }

    /// The SF Symbol shown for this pane in the window's toolbar.
    var symbol: String {
        switch self {
        case .desktop:
            return "desktopcomputer"
        case .keyboard:
            return "keyboard"
        case .input:
            return "option"
        case .excludedApps:
            return "hand.raised"
        }
    }
}

/// The selected pane's form, at the width every pane shares. The height is
/// whatever the pane's rows need; the window accommodates it, as the HIG's
/// settings guidance puts it ("a settings window accommodates the size of
/// the current pane").
struct SettingsPaneContent: View {
    let pane: SettingsPane

    var body: some View {
        content
            .frame(width: settingsPaneWidth)
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
        case .excludedApps:
            ExcludedAppsPane()
        }
    }
}

/// The panes as one tab view controller whose tabs render as the window's
/// toolbar — the same AppKit substrate the SwiftUI Settings scene builds
/// on: a centered `.preference` toolbar with one icon item per pane, the
/// selected pane's name as the window title, and the window sized to the
/// selected pane's form.
///
/// The sizing is `NSTabViewController`'s own: each pane is an
/// `NSHostingController` with `sizingOptions = [.preferredContentSize]`, so
/// the form's ideal size reaches the tab controller, which resizes the
/// window to it and holds the window's top edge across pane switches. That
/// is the whole mechanism; nothing here sets a frame.
@MainActor
private final class SettingsTabViewController: NSTabViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // No crossfade: the pane is hidden for the resize and revealed at
        // the end of it (see `resize`), so there is nothing to fade between.
        transitionOptions = []

        for pane in SettingsPane.allCases {
            let controller = NSHostingController(
                rootView: SettingsPaneContent(pane: pane))
            // preferredContentSize carries the form's ideal height up to the
            // window, which is what sizes it to the pane.
            controller.sizingOptions = [.preferredContentSize]
            controller.title = pane.title

            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }

        selectedTabViewItemIndex = Self.storedPaneIndex()
    }

    // Built in code; there is no storyboard to decode from.
    required init?(coder: NSCoder) { nil }

    /// The pane whose form is showing.
    var selectedPane: SettingsPane {
        let index = min(max(selectedTabViewItemIndex, 0), SettingsPane.allCases.count - 1)
        return SettingsPane.allCases[index]
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let item = tabViewItem,
              let index = tabViewItems.firstIndex(of: item) else { return }
        UserDefaults.standard.set(
            SettingsPane.allCases[index].rawValue, forKey: settingsSelectedPaneKey)
        guard let window = view.window else { return }
        // canPropagagateSelectedChildViewControllerTitle feeds the child's
        // title to the tab controller, but NSWindow.title only picks that up
        // when contentViewController is assigned, so set it here.
        window.title = SettingsPane.allCases[index].title
        let incoming = item.viewController
        // Blank the content for the resize; `resize` reveals it at the end.
        incoming?.view.isHidden = true
        resize(window, to: incoming)
    }

    /// Resizes the window to the incoming pane, which `didSelect` has
    /// hidden, and reveals the pane once the window is the right size. The
    /// content area stays blank for the whole resize rather than crossfading
    /// the new pane in underneath it. Hiding the pane also takes its form's
    /// scroller with it, which would otherwise appear for the length of the
    /// animation, the content being briefly taller than the window.
    ///
    /// The tab controller reaches the same height on its own, but not until
    /// the transition has finished — measured at ~650 ms after the switch,
    /// long enough that the window visibly snaps afterwards. Nothing has to
    /// be waited for: the incoming pane's `preferredContentSize` is already
    /// final when the switch begins (measured exact, with no settling).
    ///
    /// **Call this synchronously from `didSelect`, not a turn later.** Two
    /// milliseconds after the switch AppKit's constraint engine sets the
    /// window to the new pane's height itself (measured: `setFrame` from
    /// `NSWindow(NSConstraintBasedLayoutInternal)` via `NSISEngine`), and
    /// anything that runs after that finds the window already there and has
    /// nothing left to animate. Setting the frame first leaves the
    /// constraint pass with nothing to do.
    private func resize(_ window: NSWindow, to viewController: NSViewController?) {
        // Bumped on every path through here: a later resize (animated or
        // not) must cancel any pending fallback reveal an earlier one
        // scheduled, or the stale fallback would un-hide a pane the newer
        // switch just hid — the flicker the hide-during-resize design
        // exists to prevent.
        resizeGeneration += 1
        let generation = resizeGeneration
        func reveal() { viewController?.view.isHidden = false }
        guard window.isVisible,
              let ideal = viewController?.preferredContentSize.height, ideal > 1
        else { reveal(); return }
        let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        var frame = window.frame
        frame.size.height = ideal + chrome
        // A settings window grows downward from its title bar.
        frame.origin.y = window.frame.maxY - frame.height
        guard abs(frame.height - window.frame.height) > 0.5 else { reveal(); return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
            reveal()
        } else {
            var revealed = false
            NSAnimationContext.runAnimationGroup { context in
                // AppKit's own duration for a frame change of this size,
                // which scales with the distance, caps at 0.350 s, and
                // honours the NSWindowResizeTime default. It is what the
                // blocking setFrame(display:animate:) uses internally, so
                // the timing matches a window AppKit resizes itself.
                context.duration = window.animationResizeTime(frame)
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                // AppKit runs the completion handler on the main thread, but
                // does not declare it @MainActor.
                MainActor.assumeIsolated {
                    revealed = true
                    guard let self, self.resizeGeneration == generation else { return }
                    reveal()
                }
            }
            // The completion of a group whose animation never starts is
            // never delivered (measured in this app — see OSDPanel, which
            // carries the same fallback), and the pane stays hidden with
            // nothing re-triggering didSelect for an unchanged selection —
            // close the window mid-resize and reopen it, and the content
            // area is blank until a pane switch. Land the reveal directly,
            // gated on this resize still being the live one.
            let duration = window.animationResizeTime(frame)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !revealed, self.resizeGeneration == generation else { return }
                    reveal()
                }
            }
        }
    }

    /// Bumped by each pass through `resize`, so a pending fallback reveal
    /// only applies to the resize that scheduled it.
    private var resizeGeneration = 0

    /// Reopens on the pane that was last shown.
    private static func storedPaneIndex() -> Int {
        guard let stored = UserDefaults.standard.string(forKey: settingsSelectedPaneKey),
              let pane = SettingsPane(rawValue: stored),
              let index = SettingsPane.allCases.firstIndex(of: pane) else { return 0 }
        return index
    }
}

/// Owns the settings window. The window is built on first use — a menu bar
/// app may never open it — and kept afterwards, so reopening lands on the
/// pane and the position it was left at.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("superopt-settings")

    init() {
        super.init(window: nil)
    }

    // Built in code; there is no nib to decode from.
    required init?(coder: NSCoder) { nil }

    func show() {
        if window == nil {
            makeWindow()
        }
        // Plain activate() is cooperative and never activates this accessory app
        // while another app is frontmost, leaving the window behind it (measured
        // on macOS 27). The deprecated activate(ignoringOtherApps:) is the only
        // variant that works.
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    private func makeWindow() {
        let tabController = SettingsTabViewController()

        // Titled and closable but not resizable or miniaturizable, with a
        // `.preference` toolbar — the centered icon row, one item per pane.
        // NSTabViewController sizes the window to the selected pane and keeps
        // its top edge across switches; nothing here resizes it by hand.
        // No `.fullSizeContentView`: the SwiftUI Settings scene uses it, but
        // it folds the toolbar inset into its own safe-area handling — a
        // plain NSHostingController gets no safe-area information from the
        // window's contentLayoutGuide, so the form ran under the toolbar and
        // the top rows were obscured. Without it AppKit starts the content
        // below the toolbar.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: settingsPaneWidth, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .preference
        window.identifier = Self.windowIdentifier
        window.isReleasedWhenClosed = false
        window.contentViewController = tabController
        window.title = tabController.selectedPane.title
        // Lay out before centering: the window is still at its placeholder
        // height until the tab controller has applied the pane's preferred
        // content size, and centering that height would leave the window
        // low on screen once it grows (AppKit grows it downward from the
        // top edge it was given).
        window.layoutIfNeeded()
        window.center()
        shouldCascadeWindows = false
        self.window = window
    }
}
