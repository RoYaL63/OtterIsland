import Foundation
import AppKit

/// Bascule le mode Concentration (« Ne pas déranger ») de macOS.
///
/// À LIRE AVANT DE VOULOIR « SIMPLIFIER » CE FICHIER : il n'existe aucune API
/// publique pour activer Concentration depuis une app. Le réglage vivait dans
/// `com.apple.notificationcenterui` jusqu'à Big Sur ; depuis Monterey, les
/// modes de Concentration sont un service système que seuls Réglages,
/// le Centre de contrôle et l'app Raccourcis peuvent piloter. Écrire
/// directement dans `~/Library/DoNotDisturb/DB/Assertions.json` « marche »
/// parfois, casse à chaque version majeure, et n'est notifié à personne.
///
/// Le seul chemin sanctionné, et donc le seul qui survivra aux mises à jour,
/// est l'app Raccourcis : son action « Définir la concentration » fait
/// exactement ce qu'on veut, et `/usr/bin/shortcuts` sait lancer un raccourci
/// par son nom. D'où le réglage « nom du raccourci » plutôt qu'un simple
/// interrupteur : c'est l'utilisateur qui possède le raccourci.
enum FocusMode {

    /// Lance un raccourci par son nom, sans bloquer l'appelant.
    ///
    /// Silencieux à dessein : un Pomodoro ne doit pas s'interrompre parce qu'un
    /// raccourci a été renommé. L'état réel est vérifiable dans les réglages,
    /// où `availableShortcuts()` alimente le menu déroulant.
    static func trigger(_ shortcutName: String) {
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = shell(["run", name])
        }
    }

    /// Noms des raccourcis de l'utilisateur, pour le menu des réglages. Appel
    /// synchrone : la liste est courte et n'est lue qu'à l'ouverture du panneau.
    static func availableShortcuts() -> [String] {
        guard let output = shell(["list"]) else { return [] }
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    /// Ouvre l'app Raccourcis pour que l'utilisateur crée le sien.
    static func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        NSWorkspace.shared.open(url)
    }

    /// true si `/usr/bin/shortcuts` existe (il est livré avec macOS 12+, mais
    /// l'app cible macOS 14 : autant ne pas parier là-dessus en silence).
    static var isSupported: Bool {
        FileManager.default.isExecutableFile(atPath: executable)
    }

    private static let executable = "/usr/bin/shortcuts"

    private static func shell(_ arguments: [String]) -> String? {
        guard isSupported else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // ne pas polluer la console de l'app
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
