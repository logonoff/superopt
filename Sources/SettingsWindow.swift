import Cocoa
import SwiftUI

struct SettingsView: View {
    @AppStorage("optSingleEnabled") var optSingle = true
    @AppStorage("optDoubleEnabled") var optDouble = true
    @AppStorage("hotCornersEnabled") var hotCorners = true
    @AppStorage("dockShortcutsEnabled") var dockShortcuts = true
    @AppStorage("dockFinderPosition") var finderPosition = 1
    @AppStorage("lockKeyOSDEnabled") var lockKeyOSD = true
    @AppStorage("homeEndRemapEnabled") var homeEndRemap = true
    @AppStorage("zoomButtonEnabled") var zoomButton = false
    @AppStorage("finderCutEnabled") var finderCut = false
    @AppStorage("middleClickPasteEnabled") var middleClickPaste = false
    @AppStorage("gnomeShortcutsEnabled") var gnomeShortcuts = false
    @AppStorage("menuBarBgEnabled") var menuBarBg = false
    @AppStorage("SLSMenuBarUseBlurredAppearance") var systemMenuBarBgOn = false

    @StateObject private var gnomeSettings = GnomeShortcutSettings()
    @State private var expandedCategories: Set<String> = []

    var onSettingChanged: ((String, Any) -> Void)?

    var body: some View {
        Form {
            Section("Desktop") {
                Toggle(isOn: $hotCorners) {
                    Text("Hot Corner")
                    Text("Slam mouse to top-left corner → Mission Control")
                }
                .onChange(of: hotCorners) { _, val in notify("hotCornersEnabled", val) }

                Toggle(isOn: $menuBarBg) {
                    Text("Dark Menu Bar")
                    if systemMenuBarBgOn {
                        Text("Disable \"Show menu bar background\" in System Settings to use this")
                    } else {
                        Text("Black bar behind menu bar when a window fills the screen")
                    }
                }
                .disabled(systemMenuBarBgOn)
                .onChange(of: menuBarBg) { _, val in notify("menuBarBgEnabled", val) }

                Toggle(isOn: $zoomButton) {
                    Text("Green Button Fills Window")
                    Text("Green traffic light fills the window instead of entering full screen")
                }
                .onChange(of: zoomButton) { _, val in notify("zoomButtonEnabled", val) }
            }

            Section("Keyboard") {
                Toggle(isOn: $lockKeyOSD) {
                    Text("Caps Lock OSD")
                    Text("On-screen notification when Caps Lock is toggled")
                }
                .onChange(of: lockKeyOSD) { _, val in notify("lockKeyOSDEnabled", val) }

                Toggle(isOn: $homeEndRemap) {
                    Text("↖/↘ → Line Start/End")
                    Text("Home/End keys move cursor to line start/end in text fields")
                }
                .onChange(of: homeEndRemap) { _, val in notify("homeEndRemapEnabled", val) }
            }

            Section("GNOME-style Shortcuts") {
                Toggle("⌥ → Mission Control", isOn: $optSingle)
                    .onChange(of: optSingle) { _, val in notify("optSingleEnabled", val) }
                Toggle("⌥⌥ → Apps", isOn: $optDouble)
                    .onChange(of: optDouble) { _, val in notify("optDoubleEnabled", val) }

                Toggle("⌥+N → Dock App", isOn: $dockShortcuts)
                    .onChange(of: dockShortcuts) { _, val in notify("dockShortcutsEnabled", val) }
                Picker(selection: $finderPosition) {
                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                } label: {
                    Text("Finder Position")
                    Text("Which ⌥+N slot opens Finder (other apps shift to fill)")
                }
                .onChange(of: finderPosition) { _, val in notify("dockFinderPosition", val) }

                Toggle(isOn: $finderCut) {
                    Text("Cut & Paste Files in Finder")
                    Text("⌃X then ⌃V moves files instead of duplicating")
                }
                .onChange(of: finderCut) { _, val in notify("finderCutEnabled", val) }

                Toggle(isOn: $middleClickPaste) {
                    Text("Middle-click Paste")
                    Text("Middle mouse button pastes from clipboard (X11-style)")
                }
                .onChange(of: middleClickPaste) { _, val in notify("middleClickPasteEnabled", val) }

                Toggle(isOn: $gnomeShortcuts) {
                    Text("Ctrl → ⌘ Keyboard Shortcuts")
                    Text("Remap Ctrl+key to ⌘+key and other Linux-style shortcuts")
                }
                .onChange(of: gnomeShortcuts) { _, val in notify("gnomeShortcutsEnabled", val) }

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
                                            Text(shortcut.from)
                                                .foregroundStyle(.secondary)
                                            Text("▸")
                                                .foregroundStyle(.secondary.opacity(0.5))
                                            Text(shortcut.to)
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
                            Button {
                                withAnimation {
                                    if expandedCategories.contains(category) {
                                        expandedCategories.remove(category)
                                    } else {
                                        expandedCategories.insert(category)
                                    }
                                }
                            } label: {
                                Text(category)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .onChange(of: gnomeSettings.disabledShortcuts) { _, _ in
                notify("gnomeDisabledShortcuts", 0)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .frame(minHeight: 400, idealHeight: 600)
        .toggleStyle(.switch)
    }

    private func notify(_ key: String, _ value: Any) {
        onSettingChanged?(key, value)
    }
}

class SettingsWindowController: NSObject {
    private var window: NSWindow?
    private var onSettingChanged: ((String, Any) -> Void)?

    func show(onSettingChanged: @escaping (String, Any) -> Void) {
        self.onSettingChanged = onSettingChanged

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        var settingsView = SettingsView()
        settingsView.onSettingChanged = onSettingChanged

        let hostingView = NSHostingView(rootView: settingsView)

        // HIG says settings windows should auto-size to content, but our disclosure
        // groups make content height vary dramatically — resizable is more practical.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OptWin Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 400)
        window.maxSize = NSSize(width: 420, height: CGFloat.greatestFiniteMagnitude)
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}
