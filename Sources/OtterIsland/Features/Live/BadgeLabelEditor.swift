import AppKit

/// Saisie de l'étiquette d'une pastille, juste à sa droite.
///
/// Un panneau « non activant » : il prend le clavier sans faire passer
/// OtterIsland au premier plan, comme Spotlight. L'app présentée reste active
/// et retrouve la frappe dès la validation.
///
/// ↩ valide, Échap abandonne l'étiquette (la pastille reste). Un nouveau clic
/// ailleurs valide aussi : c'est le contrôleur qui appelle `commit()`.
@MainActor
final class BadgeLabelEditor: NSObject, NSTextFieldDelegate {
    private var panel: KeyablePanel?
    private var field: NSTextField?
    private var onCommit: ((String) -> Void)?

    var isEditing: Bool { panel?.isVisible == true }

    /// - Parameter anchor: point écran (repère AppKit) du bord gauche de l'étiquette.
    func begin(at anchor: NSPoint, onCommit: @escaping (String) -> Void) {
        commit()
        self.onCommit = onCommit

        let size = NSSize(width: 280, height: 30)
        let panel = self.panel ?? makePanel(size: size)
        self.panel = panel
        panel.setFrame(NSRect(x: anchor.x, y: anchor.y - size.height / 2, width: size.width, height: size.height), display: true)
        field?.stringValue = ""
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(field)
    }

    /// Valide ce qui est tapé (éventuellement rien) et referme.
    func commit() {
        guard let panel, panel.isVisible else { return }
        let text = field?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        panel.orderOut(nil)
        let callback = onCommit
        onCommit = nil
        callback?(text)
    }

    /// Abandonne l'étiquette : la pastille reste seule.
    func cancel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        let callback = onCommit
        onCommit = nil
        callback?("")
    }

    private func makePanel(size: NSSize) -> KeyablePanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(srgbRed: 0.06, green: 0.08, blue: 0.09, alpha: 0.92).cgColor
        container.layer?.cornerRadius = size.height / 2
        container.layer?.borderColor = NSColor(srgbRed: 0.37, green: 0.91, blue: 0.83, alpha: 0.8).cgColor
        container.layer?.borderWidth = 1.5

        let field = NSTextField(frame: NSRect(x: 12, y: 5, width: size.width - 24, height: 20))
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .white
        field.font = .systemFont(ofSize: 14, weight: .semibold)
        field.placeholderString = "Étiquette… (↩ valider, esc pastille seule)"
        field.placeholderAttributedString = NSAttributedString(
            string: "Étiquette… (↩ valider, esc pastille seule)",
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.45), .font: NSFont.systemFont(ofSize: 13)]
        )
        field.delegate = self
        field.cell?.lineBreakMode = .byTruncatingHead
        container.addSubview(field)
        panel.contentView = container
        self.field = field
        return panel
    }

    // MARK: NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commit()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        return false
    }
}

/// Panneau sans bordure qui accepte le clavier (un panneau borderless le
/// refuse par défaut).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
