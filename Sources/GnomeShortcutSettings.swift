import SwiftUI

@Observable
class GnomeShortcutSettings {
    var disabledShortcuts: Set<String>

    init() {
        disabledShortcuts = Set(
            UserDefaults.standard.stringArray(forKey: "gnomeDisabledShortcuts") ?? [])
    }

    func isEnabled(_ id: String) -> Bool {
        !disabledShortcuts.contains(id)
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled {
            disabledShortcuts.remove(id)
        } else {
            disabledShortcuts.insert(id)
        }
        UserDefaults.standard.set(Array(disabledShortcuts), forKey: "gnomeDisabledShortcuts")
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
