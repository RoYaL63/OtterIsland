import SwiftUI

/// Point d'entrée. L'app est un agent (LSUIElement) : pas d'icône Dock,
/// pas de fenêtre principale. Toute l'UI vit dans l'encoche via l'AppDelegate.
/// La seule scène SwiftUI est la fenêtre de réglages.
@main
struct OtterIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Une `App` doit déclarer au moins une scène, d'où ce `Settings`. Mais ce
    /// n'est PAS par lui que la fenêtre de réglages s'ouvre : dans une app
    /// agent, personne ne répond à `showSettingsWindow:` et l'appel échouait en
    /// silence. C'est `SettingsWindowController`, côté AppDelegate, qui possède
    /// la vraie fenêtre — la scène ci-dessous n'est qu'un repli si une future
    /// version de macOS se remet à savoir l'ouvrir.
    var body: some Scene {
        Settings {
            SettingsView(updater: appDelegate.updater)
                .environmentObject(appDelegate.settings)
                .environmentObject(appDelegate.settingsRouter)
        }
    }
}
