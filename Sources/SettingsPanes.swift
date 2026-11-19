import SwiftUI

// MARK: - Desktop

/// The Desktop pane: hot corner, Mission Control, spaces, tiling, and the
/// menu bar.
struct DesktopPane: View {
    @AppStorage("hotCornersEnabled") var hotCorners = true
    @AppStorage("menuBarBgEnabled") var menuBarBg = false
    /// Read only — the key belongs to the system, not to SuperOpt. Kept
    /// private so no `$systemMenuBarBgOn` binding can write it into this
    /// app's own defaults domain, where it would have no effect.
    @AppStorage("SLSMenuBarUseBlurredAppearance") private var systemMenuBarBgOn = false
    @AppStorage("zoomButtonEnabled") var zoomButton = false
    @AppStorage("spaceScrollEnabled") var spaceScroll = false
    @AppStorage("spaceIndicatorEnabled") var spaceIndicator = false
    @AppStorage("mcCloseEnabled") var mcClose = true
    @AppStorage("mcTypeToSearchMode") var mcTypeToSearchMode = MissionControlSearchMode.off.rawValue
    @AppStorage("windowTilingEnabled") var windowTiling = false
    @AppStorage("snapAssistEnabled") var snapAssist = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $hotCorners) {
                    Text("Hot corner")
                    Text("Moving the pointer to the top-left corner of any screen opens Mission Control")
                }

                Toggle(isOn: $mcClose) {
                    Text("Close windows in Mission Control")
                    Text("Close buttons appear on windows in Mission Control")
                }

                Picker(selection: $mcTypeToSearchMode) {
                    Text("Off").tag(MissionControlSearchMode.off.rawValue)
                    Text("Spotlight").tag(MissionControlSearchMode.search.rawValue)
                    Text("Apps").tag(MissionControlSearchMode.apps.rawValue)
                } label: {
                    Text("Type to search in Mission Control")
                    Text("Typing in Mission Control closes it and opens Spotlight with what you typed")
                }
            } header: {
                Text("Mission Control")
            }

            Section {
                Toggle(isOn: $spaceScroll) {
                    Text("Scroll to switch spaces")
                    Text("""
                        Scrolling over the Apple menu switches that display to the \
                        next or previous space
                        """)
                }

                Toggle(isOn: $spaceIndicator) {
                    Text("Space indicator")
                    Text("An onscreen row of dots appears when a display switches spaces")
                }
            } header: {
                Text("Spaces")
            }

            Section {
                Toggle(isOn: $zoomButton) {
                    Text("Green button fills the screen")
                    Text("""
                        Clicking the green button expands the window to fill the screen \
                        instead of entering full screen
                        """)
                }

                Toggle(isOn: $windowTiling) {
                    Text("Window tiling")
                    Text("Option-Arrow keys tile, fill, or restore windows")
                }

                Toggle(isOn: $snapAssist) {
                    Text("Tile assist")
                    Text("""
                        When you tile a window to the left or right, SuperOpt suggests \
                        windows to fill the other half
                        """)
                }
            } header: {
                Text("Windows")
            }

            Section {
                Toggle(isOn: $menuBarBg) {
                    Text("Dark menu bar")
                    if systemMenuBarBgOn {
                        Text("Turn off “Show menu bar background” in Menu Bar settings to use this feature")
                    } else {
                        Text("A black bar appears behind the menu bar when a window fills the screen")
                    }
                }
                .disabled(systemMenuBarBgOn)
            } header: {
                Text("Menu Bar")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Keyboard

/// The Keyboard pane: key behaviors (Caps Lock indicator, Home/End, the
/// Menu key) and the Linux shortcut remapper. Shortcut remapping lives
/// here rather than in its own pane because the HIG has each settings
/// pane hold "a group of related settings" (a two-row Keyboard pane next
/// to a standalone remapping pane fragments one domain).
struct KeyboardPane: View {
    /// The height of the scrolling shortcut tree, so the pane holds a
    /// constant height with every category expanded.
    private static let treeHeight: CGFloat = 320

    @AppStorage("lockKeyOSDEnabled") var lockKeyOSD = true
    @AppStorage("homeEndRemapEnabled") var homeEndRemap = true
    @AppStorage("menuKeyRightClickEnabled") var menuKeyRightClick = false
    @AppStorage("gnomeShortcutsEnabled") var gnomeShortcuts = false
    @AppStorage("vscodeTerminalEnabled") var vscodeTerminal = false

    @State private var gnomeSettings = GnomeShortcutSettings()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $lockKeyOSD) {
                    Text("Caps Lock indicator")
                    Text("An onscreen indicator appears when you turn Caps Lock on or off")
                }

                Toggle(isOn: $homeEndRemap) {
                    Text("Home and End")
                    Text("""
                        Home and End keys move the insertion point to the beginning or end of the \
                        line; Control-Home and Control-End move it to the beginning or end of the document
                        """)
                }

                Toggle(isOn: $menuKeyRightClick) {
                    Text("Menu key → shortcut menu")
                    Text("The Menu key on Windows keyboards opens a shortcut menu")
                }
            }

            Section {
                Toggle(isOn: $gnomeShortcuts) {
                    Text("Remap Linux shortcuts")
                    Text("Maps Linux keyboard shortcuts to their Mac equivalents")
                }

                if gnomeShortcuts {
                    Toggle(isOn: $vscodeTerminal) {
                        Text("Detect integrated terminals in code editors")
                        Text("""
                            Treats the integrated terminal in code editors such as VS Code and Cursor \
                            as a terminal app, so Control-C and similar shortcuts pass through unchanged
                            """)
                    }
                }
            } header: {
                Text("Shortcut Remapping")
            }

            if gnomeShortcuts {
                // In the Form, so the heading is a real AXHeading and the
                // row's insets and metrics are the Form's own, in both
                // layout directions.
                Section {
                    ShortcutOutline(settings: gnomeSettings)
                        .frame(height: Self.treeHeight)
                } header: {
                    Text("Shortcuts")
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}

// MARK: - Input

/// The Input pane: Option-key triggers, Dock shortcuts, mouse behavior, and
/// the Finder and Menu keys.
struct InputPane: View {
    @AppStorage("optSingleEnabled") var optSingle = true
    @AppStorage("optDoubleEnabled") var optDouble = true
    @AppStorage("appGridEnabled") var appGrid = true
    @AppStorage("dockShortcutsEnabled") var dockShortcuts = true
    @AppStorage("dockFinderPosition") var finderPosition = 1
    @AppStorage("finderCutMode") var finderCutMode = FinderCutMode.off.rawValue
    @AppStorage("middleClickPasteEnabled") var middleClickPaste = false
    @AppStorage("clickThroughFocusEnabled") var clickThroughFocus = false
    @AppStorage("scrollZoomMode") var scrollZoomMode = ScrollZoomMode.off.rawValue

    /// Literal Text() calls grouped in a property (not constants) so
    /// genstrings still extracts them while staying under the line limit.
    @ViewBuilder
    private var cutPasteLabel: some View {
        Text("Cut and paste files in the Finder")
        Text("Cut marks the selected files to be moved; Paste moves them to the current folder")
    }

    /// Same pattern as cutPasteLabel.
    @ViewBuilder
    private var clickThroughLabel: some View {
        Text("Click-through focus")
        Text("""
            Clicking an inactive window brings it to the front and passes the click \
            through to the item under the pointer
            """)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $optSingle) {
                    Text("⌥ → Mission Control")
                    Text("Pressing the Option key opens Mission Control")
                }
                Toggle(isOn: $optDouble) {
                    Text("⌥⌥ → Apps")
                    Text("Pressing Option twice opens the Apps view in Spotlight")
                }

                Toggle(isOn: $appGrid) {
                    Text("⌥A → Apps")
                    Text("Option-A opens the Apps view in Spotlight")
                }

                Toggle(isOn: $dockShortcuts) {
                    Text("⌥1–9 → Apps in the Dock")
                    Text("Option-1 through Option-9 open the corresponding app in the Dock")
                }
                Picker(selection: $finderPosition) {
                    // Verbatim: the row labels are the numbers 1–9, not text.
                    ForEach(1...9, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                } label: {
                    Text("Finder position")
                    Text("The Finder takes this position in the Dock; other apps shift to fill the gap")
                }
            } header: {
                Text("Option Key")
            }

            Section {
                Toggle(isOn: $middleClickPaste) {
                    Text("Middle-click paste")
                    Text("""
                        A middle click pastes the selected text, or the contents of the \
                        Clipboard if nothing is selected; middle-clicking a Dock app icon \
                        opens a new window
                        """)
                }

                Toggle(isOn: $clickThroughFocus) {
                    clickThroughLabel
                }

                Picker(selection: $scrollZoomMode) {
                    Text("Off").tag(ScrollZoomMode.off.rawValue)
                    Text("Natural").tag(ScrollZoomMode.natural.rawValue)
                    Text("Traditional").tag(ScrollZoomMode.traditional.rawValue)
                } label: {
                    Text("Scroll to zoom in browsers")
                    Text("Control-scroll zooms in and out")
                }
            } header: {
                Text("Mouse")
            }

            Section {
                Picker(selection: $finderCutMode) {
                    Text("Off").tag(FinderCutMode.off.rawValue)
                    Text("⌘X and ⌘V").tag(FinderCutMode.command.rawValue)
                    Text("⌃X and ⌃V").tag(FinderCutMode.control.rawValue)
                } label: {
                    cutPasteLabel
                }
            } header: {
                Text("Finder")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }
}
