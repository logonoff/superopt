import SwiftUI
import UniformTypeIdentifiers

// genstrings -SwiftUI only extracts Text(); Section/Toggle string labels need manual entries
private let _excludedAppsStrings = [
    NSLocalizedString("Excluded Apps", comment: "Section header"),
    NSLocalizedString("Turn Off SuperOpt in These Apps", comment: "Toggle label"),
    NSLocalizedString(
        """
        While you’re using an app in this list, SuperOpt turns off every feature \
        and dims its menu bar icon
        """,
        comment: "Toggle description"),
    NSLocalizedString("No apps are excluded.", comment: "Shown in place of an empty list of apps")
]

/// One app on the list, resolved for display.
struct ExcludedApp: Identifiable, Hashable {
    /// The bundle identifier, which is what gets stored and what the frontmost app is
    /// matched against.
    let id: String
    let name: String
    let icon: NSImage
}

@MainActor @Observable
final class ExcludedAppsModel {
    private(set) var apps: [ExcludedApp] = []

    init() { reload() }

    func reload() {
        apps = ExcludedApps.bundleIDs().map(Self.describe)
    }

    /// Adds the app at `url`, ignoring one that is already on the list.
    func add(_ url: URL) {
        guard let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        var identifiers = ExcludedApps.bundleIDs()
        guard !identifiers.contains(identifier) else { return }
        identifiers.append(identifier)
        UserDefaults.standard.set(identifiers, forKey: ExcludedApps.listKey)
        reload()
    }

    func remove(_ identifiers: Set<String>) {
        let kept = ExcludedApps.bundleIDs().filter { !identifiers.contains($0) }
        UserDefaults.standard.set(kept, forKey: ExcludedApps.listKey)
        reload()
    }

    func runAddPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = NSLocalizedString("Add", comment: "Open panel button for adding an app")
        panel.message = NSLocalizedString(
            "Select the apps you want to exclude.", comment: "Open panel message")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { add(url) }
    }

    /// An app that has since been moved or deleted keeps its identifier as its name, so
    /// the row stays there to be removed rather than vanishing from the list.
    private static func describe(_ identifier: String) -> ExcludedApp {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return ExcludedApp(
                id: identifier, name: identifier,
                icon: NSWorkspace.shared.icon(for: .applicationBundle))
        }
        return ExcludedApp(
            id: identifier,
            name: FileManager.default.displayName(atPath: url.path),
            icon: NSWorkspace.shared.icon(forFile: url.path))
    }
}

/// The settings section for the excluded apps, laid out like the app lists in System
/// Settings' privacy panes: a bordered list with an add and a remove button under it.
struct ExcludedAppsSection: View {
    @AppStorage(ExcludedApps.enabledKey) private var enabled = false
    @State private var model = ExcludedAppsModel()
    @State private var selection: Set<String> = []

    var body: some View {
        Section("Excluded Apps") {
            Toggle(isOn: $enabled) {
                Text("Turn Off SuperOpt in These Apps")
                Text("""
                    While you’re using an app in this list, SuperOpt turns off every feature \
                    and dims its menu bar icon
                    """)
            }

            VStack(alignment: .leading, spacing: 4) {
                list
                buttons
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.apps) { app in
                HStack(spacing: 6) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(verbatim: app.name)
                }
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 120)
        .overlay {
            if model.apps.isEmpty {
                Text("No apps are excluded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The two buttons System Settings puts under a list like this one: joined, with a
    /// divider between them, on a background of their own. A `ControlGroup` is what
    /// draws that; the size is the system's, so the click targets match too.
    private var buttons: some View {
        ControlGroup {
            Button {
                model.runAddPanel()
            } label: {
                Image(systemName: "plus").frame(width: Self.buttonWidth)
            }
            .accessibilityLabel(Text("Add app"))
            .help(Text("Add app"))

            Button {
                model.remove(selection)
                selection = []
            } label: {
                Image(systemName: "minus").frame(width: Self.buttonWidth)
            }
            .disabled(selection.isEmpty)
            .accessibilityLabel(Text("Remove app"))
            .help(Text("Remove app"))
        }
        .fixedSize()
    }

    /// Wide enough that the glyph is not the whole target, matching the width of the
    /// same buttons in System Settings.
    private static let buttonWidth: CGFloat = 14
}
