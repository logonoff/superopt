import SwiftUI

@MainActor @Observable
final class GnomeShortcutSettings: NSObject {
    /// The UserDefaults key, nonisolated so deinit (nonisolated by
    /// definition) can remove the KVO observation registered in init.
    nonisolated static let defaultsKey = "gnomeDisabledShortcuts"

    var disabledShortcuts: Set<String>
    /// Bumped whenever the disabled set is reloaded from UserDefaults, so
    /// the outline knows to reconfigure its rows.
    private(set) var revision = 0

    override init() {
        disabledShortcuts = Set(
            UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
        super.init()
        // KVO rather than didChangeNotification: the notification only
        // covers writes made through this process's own defaults API, so an
        // external `defaults write` never posts it (measured), while KVO on
        // the key fires for both. The observed key is an arbitrary
        // UserDefaults key with no KeyPath representation, so the
        // block-based KVO API cannot observe it.
        UserDefaults.standard.addObserver(
            self, forKeyPath: Self.defaultsKey, options: [], context: nil)
    }

    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: Self.defaultsKey)
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
            MainActor.assumeIsolated {
                guard let self else { return }
                self.disabledShortcuts = Set(
                    UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
                self.revision += 1
            }
        }
    }
    // swiftlint:enable block_based_kvo

    func isEnabled(_ id: String) -> Bool {
        !disabledShortcuts.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled {
            disabledShortcuts.remove(id)
        } else {
            disabledShortcuts.insert(id)
        }
        UserDefaults.standard.set(Array(disabledShortcuts), forKey: Self.defaultsKey)
    }

    func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isEnabled(id) ?? true },
            set: { [weak self] in self?.setEnabled(id, $0) }
        )
    }

    enum CategoryState {
        case allOn, allOff, mixed
    }

    func categoryState(_ category: String) -> CategoryState {
        let ids = GnomeShortcutHandler.shortcuts(in: category).map(\.id)
        let enabledCount = ids.filter { isEnabled($0) }.count
        if enabledCount == ids.count { return .allOn }
        if enabledCount == 0 { return .allOff }
        return .mixed
    }

    func setCategoryEnabled(_ category: String, _ enabled: Bool) {
        for shortcut in GnomeShortcutHandler.shortcuts(in: category) {
            setEnabled(shortcut.id, enabled)
        }
    }

    func categoryBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.categoryState(category) != .allOff },
            set: { [weak self] in self?.setCategoryEnabled(category, $0) }
        )
    }
}
