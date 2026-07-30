import AppKit

/// Où l'app s'exécute, et pourquoi c'est crucial : une app en quarantaine
/// lancée hors de /Applications subit l'App Translocation de macOS — elle
/// tourne depuis un chemin ALÉATOIRE en lecture seule, différent à chaque
/// lancement. Les permissions TCC (Accessibilité, Surveillance des saisies)
/// sont liées à cette identité mouvante : elles semblent cochées mais ne
/// s'appliquent jamais. Symptôme exact : « j'ai tout autorisé et ni le
/// verrouillage clavier ni le collage auto ne marchent ».
///
/// D'où la proposition au premier lancement (`promptToInstallIfNeeded`) : c'est
/// le seul moment où l'utilisateur peut encore comprendre le lien de cause à
/// effet. Après, il croit juste que l'app est cassée.
@MainActor
enum AppInstall {
    static var bundlePath: String { Bundle.main.bundlePath }

    static var isTranslocated: Bool { bundlePath.contains("/AppTranslocation/") }

    /// Lancée directement depuis l'image disque montée : cas le plus courant
    /// quand on double-clique le .dmg sans rien glisser.
    static var isOnReadOnlyVolume: Bool {
        bundlePath.hasPrefix("/Volumes/") || isTranslocated
    }

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

    private static let declinedKey = "declinedInstallInApplications"

    // MARK: Proposition au lancement

    /// Affiche la boîte de dialogue d'installation si l'app tourne hors de
    /// /Applications. Ne redemande pas si l'utilisateur a coché « ne plus
    /// demander » — le bouton reste disponible dans les réglages.
    static func promptToInstallIfNeeded() {
        guard needsRelocation else { return }
        guard !UserDefaults.standard.bool(forKey: declinedKey) else { return }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Installer OtterIsland dans Applications ?"
        alert.informativeText = """
        OtterIsland tourne depuis \(humanLocation). Tant qu'elle n'est pas dans le dossier Applications, macOS ne lui donne pas d'identité stable : les autorisations d'Accessibilité et de Surveillance des saisies que tu coches ne s'appliquent jamais, et le lancement au démarrage ne tient pas.

        OtterIsland peut s'y déplacer toute seule et redémarrer. Ça prend deux secondes.
        """
        alert.addButton(withTitle: "Installer et redémarrer")
        alert.addButton(withTitle: "Plus tard")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Ne plus me le proposer"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: declinedKey)
        }
        guard response == .alertFirstButtonReturn else { return }

        if let failure = installInApplications() {
            reportFailure(failure)
        }
    }

    /// L'installation a échoué : on le dit, et on ouvre le Finder aux deux
    /// endroits pour que le glisser-déposer manuel prenne dix secondes.
    private static func reportFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Installation impossible"
        alert.informativeText = "\(message)\n\nTu peux glisser OtterIsland dans Applications à la main : les deux fenêtres viennent de s'ouvrir."
        alert.addButton(withTitle: "OK")
        alert.runModal()

        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: Installation

    /// Copie l'app dans /Applications, lance la copie et quitte celle-ci.
    /// Renvoie nil en cas de succès, sinon le message d'erreur à afficher.
    @discardableResult
    static func installInApplications() -> String? {
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let dest = applications.appendingPathComponent("OtterIsland.app")
        let src = Bundle.main.bundleURL
        let fm = FileManager.default

        guard fm.isWritableFile(atPath: applications.path) else {
            return "Le dossier Applications n'est pas modifiable par ton compte."
        }

        do {
            // Une ancienne copie part à la CORBEILLE, elle n'est pas détruite :
            // si quelque chose tourne mal, la version précédente est encore là.
            if fm.fileExists(atPath: dest.path) {
                try fm.trashItem(at: dest, resultingItemURL: nil)
            }
            try fm.copyItem(at: src, to: dest)
        } catch {
            return error.localizedDescription
        }

        clearQuarantine(at: dest)

        // Le zip d'origine reste dans les Téléchargements, mais l'app copiée,
        // elle, n'a plus de raison d'exister en double. Impossible depuis une
        // image disque ou un volume translocaté (lecture seule) : on laisse.
        if !isOnReadOnlyVolume {
            try? fm.trashItem(at: src, resultingItemURL: nil)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, error in
            DispatchQueue.main.async {
                if error == nil { NSApp.terminate(nil) }
            }
        }
        return nil
    }

    /// Retire l'attribut de quarantaine de la copie installée.
    ///
    /// Ce n'est pas un contournement de Gatekeeper : le code tourne DÉJÀ, donc
    /// l'utilisateur a forcément franchi Gatekeeper pour cette même app. Sans
    /// ça, la copie hérite de la quarantaine du téléchargement et macOS la
    /// bloque à nouveau au lancement suivant — alors qu'il vient d'exécuter
    /// exactement le même binaire. C'est ce que fait tout installeur macOS.
    private static func clearQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}
