import ServiceManagement

/// Gère le lancement automatique au démarrage via SMAppService (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS a accepté l'inscription mais demande une validation manuelle de
    /// l'utilisateur (Réglages Système › Général › Éléments de connexion).
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Renvoie un message d'erreur si l'inscription échoue, sinon nil.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            NSLog("OtterIsland: lancement au démarrage impossible — \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
