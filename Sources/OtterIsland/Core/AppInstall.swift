import AppKit

/// Où l'app s'exécute, et pourquoi c'est crucial : une app en quarantaine
/// lancée hors de /Applications subit l'App Translocation de macOS — elle
/// tourne depuis un chemin ALÉATOIRE en lecture seule, différent à chaque
/// lancement. Les permissions TCC (Accessibilité, Surveillance des saisies)
/// sont liées à cette identité mouvante : elles semblent cochées mais ne
/// s'appliquent jamais. Symptôme exact : « j'ai tout autorisé et ni le
/// verrouillage clavier ni le collage auto ne marchent ».
@MainActor
enum AppInstall {
    static var bundlePath: String { Bundle.main.bundlePath }

    static var isTranslocated: Bool { bundlePath.contains("/AppTranslocation/") }

    static var isInApplications: Bool {
        bundlePath.hasPrefix("/Applications/")
    }

    /// true si les permissions ne peuvent pas fonctionner de façon fiable.
    static var needsRelocation: Bool { !isInApplications }

    /// Dossier d'origine lisible pour l'utilisateur (ex. « Téléchargements »).
    static var humanLocation: String {
        if isTranslocated { return "un volume temporaire (App Translocation)" }
        let url = Bundle.main.bundleURL.deletingLastPathComponent()
        return url.lastPathComponent
    }

    /// Copie l'app dans /Applications, lance la copie et quitte celle-ci.
    /// Si la copie échoue (droits), ouvre simplement /Applications pour un
    /// glisser-déposer manuel.
    static func installInApplications() {
        let dest = URL(fileURLWithPath: "/Applications/OtterIsland.app")
        let src = Bundle.main.bundleURL
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: src, to: dest)
        } catch {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
