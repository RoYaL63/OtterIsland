import AppKit
import SwiftUI

/// Fenêtre de réglages, possédée par l'app.
///
/// POURQUOI ELLE EXISTE : ni « Réglages OtterIsland… » ni « Rechercher les
/// mises à jour… » n'ouvraient quoi que ce soit. Les deux passaient par
/// `NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)`,
/// le mécanisme qui demande à la scène `Settings` de SwiftUI de se montrer.
/// Avec `to: nil`, AppKit remonte la chaîne des réponses jusqu'au menu
/// principal pour trouver qui sait répondre — sauf qu'OtterIsland est une app
/// agent (`LSUIElement`, politique `.accessory`) : elle n'a ni menu principal
/// ni fenêtre clé. Personne ne répond, `sendAction` renvoie `false`, et rien ne
/// se passe. Le retour n'était même pas lu, d'où l'échec silencieux.
///
/// La fenêtre « À propos » marchait précisément parce qu'elle ne demande rien à
/// personne : elle possède sa `NSWindow`. On fait pareil ici, et la question de
/// savoir quel sélecteur macOS accepte cette année ne se pose plus.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    private let settings: OtterSettings
    private let router: SettingsRouter
    private let updater: Updater

    init(settings: OtterSettings, router: SettingsRouter, updater: Updater) {
        self.settings = settings
        self.router = router
        self.updater = updater
    }

    /// Ouvre la fenêtre sur l'onglet demandé. L'onglet est posé AVANT
    /// `makeKeyAndOrderFront` : à la première ouverture la vue n'existe pas
    /// encore, elle lit le routeur à sa création.
    func show(tab: SettingsTab) {
        router.tab = tab
        let win = window ?? makeWindow()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(updater: updater)
            .environmentObject(settings)
            .environmentObject(router)
        let host = NSHostingView(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Réglages — OtterIsland"
        win.contentView = host
        // Une app agent n'a pas de cycle de vie de fenêtre classique : sans ça,
        // fermer les réglages détruirait la fenêtre et la rouvrir planterait.
        win.isReleasedWhenClosed = false
        win.center()
        return win
    }
}
