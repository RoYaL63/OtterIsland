import AppKit
import CoreGraphics
import ApplicationServices

/// Simule un collage (Cmd+V) dans l'app active. Demande la permission Accessibilité.
enum Paster {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Ouvre la demande de permission Accessibilité si nécessaire.
    /// On passe la clé en littéral pour éviter les différences d'import du symbole
    /// kAXTrustedCheckOptionPrompt selon les versions du SDK.
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Envoie Cmd+V à l'app frontale. Sans permission, ne fait rien (l'item reste
    /// dans le presse-papier, l'utilisateur peut coller à la main).
    static func paste() {
        guard hasAccessibility else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
