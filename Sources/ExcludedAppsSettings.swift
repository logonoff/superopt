import SwiftUI
import UniformTypeIdentifiers

// genstrings -SwiftUI only extracts Text(); Section/Toggle string labels need manual entries
private let _excludedAppsStrings = [
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

/// The settings pane for the excluded apps, laid out like the app lists in
/// System Settings' privacy panes: the apps as section rows with a +/− footer
/// row under them.
struct ExcludedAppsPane: View {
    @AppStorage(ExcludedApps.enabledKey) private var enabled = false
    @State private var model = ExcludedAppsModel()
    @State private var selected: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Turn Off SuperOpt in These Apps")
                    Text("""
                        While you’re using an app in this list, SuperOpt turns off every feature \
                        and dims its menu bar icon
                        """)
                }

                ForEach(model.apps) { app in
                    ZStack(alignment: .leading) {
                        if selected == app.id {
                            Color.accentColor.opacity(0.3)
                        }
                        HStack(spacing: 6) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(verbatim: app.name)
                        }
                        .padding(.horizontal, 10)
                    }
                    .padding(.horizontal, -10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = selected == app.id ? nil : app.id }
                }

                if model.apps.isEmpty {
                    Text("No apps are excluded.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // The +/− pair sits in a plain row, independent of the card's
                // padding — like Finder's settings windows, not glued to the
                // card's edges as the Privacy & Security panes' footer is.
                buttons
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
    }

    /// The +/− pair from System Settings' Privacy & Security panes, measured
    /// from the real app: bare borderless glyph buttons with a 1 pt divider
    /// between them, 7 pt apart — no bezel or capsule at rest.
    private var buttons: some View {
        HStack(spacing: 7) {
            Button {
                model.runAddPanel()
            } label: {
                Label("Add app", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(Text("Add app"))

            Divider()
                .frame(height: 16)

            Button {
                if let selected {
                    model.remove([selected])
                    self.selected = nil
                }
            } label: {
                Label("Remove app", systemImage: "minus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(selected == nil)
            .help(Text("Remove app"))
        }
    }
}
