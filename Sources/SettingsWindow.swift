import Cocoa
import SwiftUI

private extension View {
    @ViewBuilder
    func mixed(_ isMixed: Bool) -> some View {
        if isMixed {
            self.allowsHitTesting(true)
                .overlay(alignment: .leading) {
                    Image(systemName: "minus.square.fill")
                        .foregroundStyle(.white, .tint)
                        .allowsHitTesting(false)
                }
        } else {
            self
        }
    }
}

// genstrings -SwiftUI only extracts Text(); Section/Toggle string labels need manual entries
private let _extraStrings = [
    NSLocalizedString("Desktop", comment: "Section header"),
    NSLocalizedString("Keyboard", comment: "Section header"),
    NSLocalizedString("Input", comment: "Section header"),
    NSLocalizedString("Shortcut Remapping", comment: "Section header"),
    NSLocalizedString("⌥ → Mission Control", comment: "Toggle label"),
    NSLocalizedString("⌥⌥ → Apps", comment: "Toggle label"),
    NSLocalizedString("Window Tiling", comment: "Toggle label"),
    NSLocalizedString("⌥+N → Dock App", comment: "Toggle label"),
    NSLocalizedString("Copy, paste, undo, find, and other essentials", comment: "Category hint"),
    NSLocalizedString("New, save, print, and quit", comment: "Category hint"),
    NSLocalizedString("Zoom and full screen", comment: "Category hint"),
    NSLocalizedString("Word-level navigation, deletion, and formatting", comment: "Category hint"),
    NSLocalizedString("Active only in Finder", comment: "Category hint"),
    NSLocalizedString("Tab and window management", comment: "Category hint"),
    NSLocalizedString("Active only in browsers", comment: "Category hint"),
    NSLocalizedString("Active only in terminal apps", comment: "Category hint"),
    NSLocalizedString("Active only in code editors", comment: "Category hint"),
    NSLocalizedString("Off", comment: "Scroll zoom picker option"),
    NSLocalizedString("Natural", comment: "Scroll zoom picker option"),
    NSLocalizedString("Traditional", comment: "Scroll zoom picker option"),
    NSLocalizedString("Scroll Zoom in Browsers", comment: "Picker label"),
    NSLocalizedString("⌃Scroll zooms in and out in browser apps", comment: "Picker description"),
    NSLocalizedString("Menu Key → Shortcut Menu", comment: "Toggle label"),
    NSLocalizedString("The Menu key on PC keyboards opens a shortcut menu", comment: "Toggle description")
]

struct SettingsView: View {
    @AppStorage("optSingleEnabled") var optSingle = true
    @AppStorage("optDoubleEnabled") var optDouble = true
    @AppStorage("hotCornersEnabled") var hotCorners = true
    @AppStorage("appGridEnabled") var appGrid = true
    @AppStorage("dockShortcutsEnabled") var dockShortcuts = true
    @AppStorage("dockFinderPosition") var finderPosition = 1
    @AppStorage("lockKeyOSDEnabled") var lockKeyOSD = true
    @AppStorage("homeEndRemapEnabled") var homeEndRemap = true
    @AppStorage("windowTilingEnabled") var windowTiling = false
    @AppStorage("zoomButtonEnabled") var zoomButton = false
    @AppStorage("finderCutEnabled") var finderCut = false
    @AppStorage("middleClickPasteEnabled") var middleClickPaste = false
    @AppStorage("scrollZoomMode") var scrollZoomMode = ScrollZoomMode.off.rawValue
    @AppStorage("menuKeyRightClickEnabled") var menuKeyRightClick = false
    @AppStorage("gnomeShortcutsEnabled") var gnomeShortcuts = false
    @AppStorage("menuBarBgEnabled") var menuBarBg = false
    @AppStorage("SLSMenuBarUseBlurredAppearance") var systemMenuBarBgOn = false

    @State private var gnomeSettings = GnomeShortcutSettings()
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        Form {
            Section("Desktop") {
                Toggle(isOn: $hotCorners) {
                    Text("Hot Corner")
                    Text("Moving the mouse to the top-left corner opens Mission Control")
                }

                Toggle(isOn: $menuBarBg) {
                    Text("Dark Menu Bar")
                    if systemMenuBarBgOn {
                        Text("Turn off Show Menu Bar Background in System Settings to use this")
                    } else {
                        Text("Shows a black bar behind the menu bar when a window fills the screen")
                    }
                }
                .disabled(systemMenuBarBgOn)

                Toggle(isOn: $zoomButton) {
                    Text("Green Button Fills Window")
                    Text("Clicking the green button fills the window instead of entering full screen")
                }

                Toggle(isOn: $windowTiling) {
                    Text("Window Tiling")
                    Text("⌥+Arrow keys tile, maximize, or restore windows")
                }
            }

            Section("Keyboard") {
                Toggle(isOn: $lockKeyOSD) {
                    Text("Caps Lock OSD")
                    Text("Shows an on-screen notification when Caps Lock is toggled")
                }

                Toggle(isOn: $homeEndRemap) {
                    Text("↖/↘ → Line Start/End")
                    Text("Home and End keys move the cursor to the start or end of the line")
                }
            }

            Section("Input") {
                Toggle(isOn: $optSingle) {
                    Text("⌥ → Mission Control")
                    Text("Single press Option to open Mission Control")
                }
                Toggle(isOn: $optDouble) {
                    Text("⌥⌥ → Apps")
                    Text("Double press Option to open Spotlight Apps")
                }

                Toggle(isOn: $appGrid) {
                    Text("⌥A → Apps")
                    Text("Option+A opens Spotlight Apps")
                }

                Toggle(isOn: $dockShortcuts) {
                    Text("⌥+N → Dock App")
                    Text("Option plus a number key launches the corresponding Dock app")
                }
                Picker(selection: $finderPosition) {
                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                } label: {
                    Text("Finder Position")
                    Text("Dock position assigned to Finder — other apps shift to fill")
                }

                Toggle(isOn: $finderCut) {
                    Text("Cut & Paste Files in Finder")
                    Text("⌃X copies files for moving, ⌃V moves them to the current folder")
                }

                Toggle(isOn: $middleClickPaste) {
                    Text("Middle-Click Paste")
                    Text("Paste with middle-click, or open a new window from the Dock")
                }

                Toggle(isOn: $menuKeyRightClick) {
                    Text("Menu Key → Shortcut Menu")
                    Text("The Menu key on PC keyboards opens a shortcut menu")
                }

                Picker(selection: $scrollZoomMode) {
                    Text("Off").tag(ScrollZoomMode.off.rawValue)
                    Text("Natural").tag(ScrollZoomMode.natural.rawValue)
                    Text("Traditional").tag(ScrollZoomMode.traditional.rawValue)
                } label: {
                    Text("Scroll Zoom in Browsers")
                    Text("⌃Scroll zooms in and out in browser apps")
                }
            }

            Section("Shortcut Remapping") {
                Toggle(isOn: $gnomeShortcuts) {
                    Text("Remap Shortcuts")
                    Text("Maps Linux keyboard shortcuts to their Mac equivalents")
                }

                if gnomeShortcuts {
                    ForEach(GnomeShortcutHandler.categories, id: \.self) { category in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedCategories.contains(category) },
                                set: { expanded in
                                    withAnimation {
                                        if expanded {
                                            expandedCategories.insert(category)
                                        } else {
                                            expandedCategories.remove(category)
                                        }
                                    }
                                }
                            )
                        ) {
                            ForEach(GnomeShortcutHandler.shortcuts(in: category)) { shortcut in
                                Toggle(isOn: gnomeSettings.binding(for: shortcut.id)) {
                                    HStack {
                                        Text(shortcut.label)
                                            .frame(width: 130, alignment: .leading)
                                        HStack(spacing: 4) {
                                            Text(shortcut.fromKeys)
                                                .foregroundStyle(.secondary)
                                            Text("▸")
                                                .foregroundStyle(.secondary.opacity(0.5))
                                            Text(shortcut.toKeys)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .toggleStyle(.checkbox)
                                .frame(height: 20)
                            }
                        } label: {
                            CategoryLabel(
                                category: category,
                                hint: Self.categoryHints[category],
                                settings: gnomeSettings,
                                expandedCategories: $expandedCategories
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .frame(minHeight: 400, idealHeight: 600)
        .toggleStyle(.switch)
    }

    private static let categoryHints: [String: String] = [
        NSLocalizedString("General", comment: "Shortcut category"):
            NSLocalizedString("Copy, paste, undo, find, and other essentials", comment: "Category hint"),
        NSLocalizedString("File", comment: "Shortcut category"):
            NSLocalizedString("New, save, print, and quit", comment: "Category hint"),
        NSLocalizedString("View", comment: "Shortcut category"):
            NSLocalizedString("Zoom and full screen", comment: "Category hint"),
        NSLocalizedString("Text Editing", comment: "Shortcut category"):
            NSLocalizedString("Word-level navigation, deletion, and formatting", comment: "Category hint"),
        NSLocalizedString("Finder", comment: "Shortcut category"):
            NSLocalizedString("Active only in Finder", comment: "Category hint"),
        NSLocalizedString("Tabs & Windows", comment: "Shortcut category"):
            NSLocalizedString("Tab and window management", comment: "Category hint"),
        NSLocalizedString("Browsers", comment: "Shortcut category"):
            NSLocalizedString("Active only in browsers", comment: "Category hint"),
        NSLocalizedString("Terminal", comment: "Shortcut category"):
            NSLocalizedString("Active only in terminal apps", comment: "Category hint"),
        NSLocalizedString("Code Editor", comment: "Shortcut category"):
            NSLocalizedString("Active only in code editors", comment: "Category hint")
    ]
}

private struct CategoryLabel: View {
    let category: String
    let hint: String?
    var settings: GnomeShortcutSettings
    @Binding var expandedCategories: Set<String>

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: settings.categoryBinding(category)) { EmptyView() }
                .toggleStyle(.checkbox)
                .mixed(settings.categoryState(category) == .mixed)
                .padding(.leading, 4)

            Button {
                withAnimation {
                    if expandedCategories.contains(category) {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category)
                    if let hint {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

@MainActor
class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())

        // HIG says settings windows should auto-size to content, but our disclosure
        // groups make content height vary dramatically — resizable is more practical.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Settings", comment: "Settings window title")
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 420, height: 400)
        window.maxSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
