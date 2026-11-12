import Cocoa

/// Caps Lock on-screen display, after gnome-shell-extension-lockkeys: a pill saying
/// which way the key just went, dimmed when it went off.
@MainActor
class LockKeyOSD {
    private static let size = NSSize(width: 220, height: 80)

    private let panel = OSDPanel(displayDuration: 1.5, fadeDuration: 0.2)

    func show(text: String, active: Bool) {
        panel.show(size: Self.size, on: NSScreen.screens, announcement: text) { view in
            let label = view.subviews.compactMap { $0 as? NSTextField }.first ?? Self.label(in: view)
            label.stringValue = text
            label.alphaValue = active ? 1.0 : 0.4
        }
    }

    private static func label(in view: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 20, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return label
    }
}
