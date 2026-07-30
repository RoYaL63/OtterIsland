import SwiftUI

/// Point d'entrée. L'app est un agent (LSUIElement) : pas d'icône Dock,
/// pas de fenêtre principale. Toute l'UI vit dans l'encoche via l'AppDelegate.
/// La seule scène SwiftUI est la fenêtre de réglages.
@main
struct OtterIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(updater: appDelegate.updater)
                .environmentObject(appDelegate.settings)
        }
    }
}
