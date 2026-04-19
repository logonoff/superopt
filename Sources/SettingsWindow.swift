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
    @AppStorage("menuBarBgEnabled") var menuBarBg = false

    var onSettingChanged: ((String, Any) -> Void)?

    private var systemMenuBarBgOn: Bool {
        UserDefaults.standard.bool(forKey: "SLSMenuBarUseBlurredAppearance")
    }

    var body: some View {
        Form {
            Section("Option Key") {
                Toggle("⌥ → Mission Control", isOn: $optSingle)
                    .onChange(of: optSingle) { _, val in notify("optSingleEnabled", val) }
                Toggle("⌥⌥ → Apps", isOn: $optDouble)
                    .onChange(of: optDouble) { _, val in notify("optDoubleEnabled", val) }
            }

            Section("Dock Shortcuts") {
                Toggle("⌥+N → Dock App", isOn: $dockShortcuts)
                    .onChange(of: dockShortcuts) { _, val in notify("dockShortcutsEnabled", val) }
                Picker("Finder Position", selection: $finderPosition) {
                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                }
                .onChange(of: finderPosition) { _, val in notify("dockFinderPosition", val) }
                .help("Which ⌥+N slot opens Finder")
            }

            Section("Desktop") {
                Toggle(isOn: $hotCorners) {
                    Text("Hot Corner")
                    Text("Slam mouse to top-left corner → Mission Control")
                }
                .onChange(of: hotCorners) { _, val in notify("hotCornersEnabled", val) }

                Toggle(isOn: $menuBarBg) {
                    Text("Dark Menu Bar")
                    Text("Black bar behind menu bar when a window fills the screen")
                }
                .disabled(systemMenuBarBgOn)
                .onChange(of: menuBarBg) { _, val in notify("menuBarBgEnabled", val) }
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
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 480)
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OptWin Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }
}
