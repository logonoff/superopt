import SwiftUI
import UniformTypeIdentifiers

/// One app on the list, resolved for display.
struct ExcludedApp: Identifiable, Hashable {
    /// The bundle identifier, which is what gets stored and what the frontmost app is
    /// matched against.
    let id: String
    let name: String
    let icon: NSImage
}

@MainActor @Observable
final class ExcludedAppsModel: NSObject {
    private(set) var apps: [ExcludedApp] = []

    override init() {
        super.init()
        reload()
        // KVO rather than didChangeNotification: the notification only
        // covers writes made through this process's own defaults API, so an
        // external `defaults write` never posts it (measured), while KVO on
        // the key fires for both — GnomeShortcutSettings observes its own
        // key the same way.
        UserDefaults.standard.addObserver(
            self, forKeyPath: ExcludedApps.listKey, options: [], context: nil)
    }

    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: ExcludedApps.listKey)
    }

    // swiftlint:disable block_based_kvo
    // Arbitrary UserDefaults keys have no KeyPath representation, so the
    // block-based KVO API cannot observe them and the selector-based
    // override is the only route.
    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
    }
    // swiftlint:enable block_based_kvo

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

/// The settings pane for the excluded apps: the apps as section rows with a
/// +/− footer row under them.
struct ExcludedAppsPane: View {
    @AppStorage(ExcludedApps.enabledKey) private var enabled = false
    @State private var model = ExcludedAppsModel()
    @State private var selected: String?

    /// The selection, dropped when the app it names has left the list — the
    /// list can change out from under the pane (an external defaults write),
    /// and a stale selection would leave the remove button enabled with
    /// nothing to remove.
    private var effectiveSelected: String? {
        guard let selected, model.apps.contains(where: { $0.id == selected })
        else { return nil }
        return selected
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    Text("Turn off SuperOpt in these apps", comment: "Toggle label")
                    Text("""
                        While you’re using an app in this list, SuperOpt turns off every feature \
                        and dims its own menu bar icon
                        """, comment: "Toggle description")
                }

                ForEach(model.apps) { app in
                    ZStack(alignment: .leading) {
                        if effectiveSelected == app.id {
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
                    Text("No apps are excluded.", comment: "Shown in place of an empty list of apps")
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

    /// The +/− pair under the list: one NSSegmentedControl with two 24 pt
    /// segments carrying add/remove template glyphs in a 49×24 pt rounded
    /// control, the remove segment disabled with nothing selected, sitting
    /// left-aligned under the list.
    private var buttons: some View {
        AddRemoveSegment(
            removeEnabled: effectiveSelected != nil,
            onAdd: { model.runAddPanel() },
            onRemove: {
                if let effectiveSelected {
                    model.remove([effectiveSelected])
                    self.selected = nil
                }
            })
            // The Form row proposes its full width; a segmented control is
            // only as wide as its segments, so hold it to its intrinsic size.
            .fixedSize()
    }
}

/// An add/remove segmented control bridged for SwiftUI: two segments with
/// `NSAddTemplate`/`NSRemoveTemplate` glyphs, reporting clicks through
/// callbacks.
private struct AddRemoveSegment: NSViewRepresentable {
    let removeEnabled: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAdd: onAdd, onRemove: onRemove)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .rounded
        control.trackingMode = .momentary
        control.segmentCount = 2
        let add = NSLocalizedString("Add an app", comment: "Add button tooltip")
        let remove = NSLocalizedString("Remove the selected app", comment: "Remove button tooltip")
        // Symbol images, not NSImage(named: NSImage.addTemplateName): the
        // named lookup returns a process-wide cached instance, so setting an
        // accessibility description on it renames NSAddTemplate for every
        // other use of it in the process, AppKit's own included (verified:
        // two lookups return the same object, and the second sees the first's
        // description). A symbol image is created per call and takes the
        // description as an initializer argument.
        control.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: add), forSegment: 0)
        control.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: remove), forSegment: 1)
        control.setToolTip(add, forSegment: 0)
        control.setToolTip(remove, forSegment: 1)
        control.setEnabled(false, forSegment: 1)
        control.target = context.coordinator
        control.action = #selector(Coordinator.clicked(_:))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        control.setEnabled(removeEnabled, forSegment: 1)
        context.coordinator.onAdd = onAdd
        context.coordinator.onRemove = onRemove
    }

    final class Coordinator: NSObject {
        var onAdd: () -> Void
        var onRemove: () -> Void

        init(onAdd: @escaping () -> Void, onRemove: @escaping () -> Void) {
            self.onAdd = onAdd
            self.onRemove = onRemove
        }

        @objc func clicked(_ sender: NSSegmentedControl) {
            if sender.selectedSegment == 0 {
                onAdd()
            } else {
                onRemove()
            }
        }
    }
}
