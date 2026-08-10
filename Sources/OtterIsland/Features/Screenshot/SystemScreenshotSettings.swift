import Foundation

/// La vignette flottante de macOS — celle qui apparaît en bas à droite après
/// ⌘⇧4 — et pourquoi elle rend la capture lente à arriver dans le presse-papier.
///
/// Tant qu'elle est affichée, `screencapture` GARDE l'image et n'écrit rien sur
/// le disque : c'est seulement quand la vignette disparaît (environ 5 secondes)
/// ou qu'on la balaie que le fichier est créé. Aucune app ne peut voir la
/// capture avant, quelle que soit la finesse de sa surveillance de dossier —
/// il n'y a littéralement rien à voir. C'est la seule cause du délai, et le
/// seul remède est de désactiver la vignette (⌘⇧5 › Options › Afficher la
/// vignette flottante, ou cet interrupteur).
///
/// Le troc est net : on perd le petit aperçu Apple et son annotation rapide, on
/// gagne une capture disponible immédiatement — et l'aperçu d'OtterIsland, lui,
/// s'affiche tout de suite et propose glisser-déposer, copie et ouverture.
enum SystemScreenshotSettings {

    private static let domain = "com.apple.screencapture"
    private static let key = "show-thumbnail"

    /// true si la vignette flottante est active. Absent des préférences = actif
    /// (c'est le comportement par défaut de macOS).
    static var floatingThumbnailEnabled: Bool {
        guard let defaults = UserDefaults(suiteName: domain),
              defaults.object(forKey: key) != nil
        else { return true }
        return defaults.bool(forKey: key)
    }

    /// Écrit la préférence via `/usr/bin/defaults` plutôt que par `UserDefaults`.
    /// Ce n'est pas de la superstition : `cfprefsd` garde en cache les domaines
    /// des autres apps, et une écriture directe peut rester invisible du
    /// processus qui la lira. L'outil système, lui, passe par le démon.
    ///
    /// Aucun `killall` : `screencapture` relit la préférence à chaque capture,
    /// le changement s'applique dès la suivante. Redémarrer SystemUIServer
    /// ferait clignoter toute la barre des menus pour rien.
    @discardableResult
    static func setFloatingThumbnail(_ enabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", domain, key, "-bool", enabled ? "true" : "false"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
