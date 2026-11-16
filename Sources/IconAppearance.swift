import Cocoa
import SwiftUI

/// The system-wide app icon appearance — System Settings → Appearance →
/// "Icon, widget & folder color" (default / clear / tinted, each in light and
/// dark variants). The preference is undocumented but its string values are
/// stable, and with no public rendering API, re-rendering from it is how
/// Apple's own panes follow the setting.
///
/// `AppleIconAppearanceTheme` holds `<Style><Variant>` — Regular, Clear or
/// Tinted, each Automatic/Light/Dark ("Dark" in the UI is the clear-dark
/// variant; an absent key means the default). Automatic resolves against the
/// system appearance. `AppleIconAppearanceTintColor` picks the tint
/// (Automatic resolves to the accent color).
@MainActor @Observable
final class IconAppearance {
    static let shared = IconAppearance()

    private(set) var mode: Mode = .regularLight
    private(set) var tintColor: Color = .accentColor

    private var pollTimer: Timer?

    enum Mode {
        case regularLight
        case regularDark
        case clearLight
        case clearDark
        case tintedLight
        case tintedDark
    }

    init() {
        update()
    }

    /// Starts following the setting. The system posts
    /// NSWorkspaceIconAppearanceConfigurationDidChangeNotification on the
    /// distributed center when it changes, but on this macOS it does not
    /// always fire for real System Settings clicks, so poll the preference
    /// as well.
    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(update),
            name: NSNotification.Name("NSWorkspaceIconAppearanceConfigurationDidChangeNotification"),
            object: nil)
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.update() }
        }
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func update() {
        let theme = UserDefaults.standard.string(forKey: "AppleIconAppearanceTheme") ?? "RegularAutomatic"
        mode = Self.mode(forTheme: theme)
        tintColor = Self.resolveTint()
    }

    private static func mode(forTheme theme: String) -> Mode {
        switch (style(forTheme: theme), isDarkVariant(forTheme: theme)) {
        case ("Regular", false):
            return .regularLight
        case ("Regular", true):
            return .regularDark
        case ("Clear", false):
            return .clearLight
        case ("Clear", true):
            return .clearDark
        case ("Tinted", false):
            return .tintedLight
        case ("Tinted", true):
            return .tintedDark
        default:
            return .regularLight
        }
    }

    private static func style(forTheme theme: String) -> String {
        if theme.hasPrefix("Tinted") {
            return "Tinted"
        } else if theme.hasPrefix("Clear") {
            return "Clear"
        }
        return "Regular"
    }

    private static func isDarkVariant(forTheme theme: String) -> Bool {
        if theme.hasSuffix("Light") {
            return false
        } else if theme.hasSuffix("Dark") {
            return true
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// The tint colour the system resolves for the pane's folder-colour
    /// picker. A custom colour is stored in a private archive format, so it
    /// falls back to the accent colour.
    private static func resolveTint() -> Color {
        let name = UserDefaults.standard.string(forKey: "AppleIconAppearanceTintColor") ?? "Automatic"
        switch name {
        case "Red":
            return Color(nsColor: .systemRed)
        case "Orange":
            return Color(nsColor: .systemOrange)
        case "Yellow":
            return Color(nsColor: .systemYellow)
        case "Green":
            return Color(nsColor: .systemGreen)
        case "Blue":
            return Color(nsColor: .systemBlue)
        case "Purple":
            return Color(nsColor: .systemPurple)
        case "Pink":
            return Color(nsColor: .systemPink)
        case "Graphite":
            return Color(white: 0.55)
        default:
            return Color(nsColor: .controlAccentColor)
        }
    }
}
