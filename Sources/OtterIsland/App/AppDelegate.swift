import AppKit

/// Monte la fenêtre d'encoche, un item de barre d'état, et garde les providers en vie.
/// Tout ici tourne sur le thread principal (AppKit, NSPanel) : @MainActor lève
/// l'ambiguïté d'isolation d'acteur avec NotchWindowController.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = OtterSettings()
    let updater = Updater()
    private var notchController: NotchWindowController?
    private var clipboardWindow: ClipboardWindowController?
    private var aboutWindow: AboutWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent : ni Dock ni menu principal.
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchWindowController(settings: settings)
        controller.showOnActiveScreen()
        notchController = controller
        clipboardWindow = ClipboardWindowController(clipboard: controller.viewModel.clipboard)

        setupStatusItem()

        // Proposition d'installation dans /Applications, au premier lancement
        // seulement. Après le montage de l'encoche : la boîte de dialogue est
        // modale, elle bloquerait la mise en place de la fenêtre.
        DispatchQueue.main.async {
            AppInstall.promptToInstallIfNeeded()
        }

        // Un seul appel GitHub au lancement ; le résultat s'affiche dans
        // l'onglet Mise à jour des réglages.
        if settings.autoCheckUpdates {
            updater.check()
        }

        // Repositionner quand l'agencement d'écran change (résolution, écran externe).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Loutre de la barre de menus. Clic GAUCHE : le presse-papier s'ouvre
    /// directement dans l'encoche (l'usage n°1). Clic DROIT : le menu complet
    /// (presse-papier en fenêtre, à propos, réglages, quitter). On n'assigne
    /// PAS `item.menu`, sinon il s'ouvrirait sur les deux clics et le clic
    /// gauche perdrait son raccourci.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🦦"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(withTitle: "Presse-papier…", action: #selector(openClipboardWindow), keyEquivalent: "")
        menu.addItem(withTitle: "À propos d'OtterIsland…", action: #selector(openAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Rechercher les mises à jour…", action: #selector(openUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Réglages OtterIsland…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter OtterIsland", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != #selector(NSApp.terminate(_:)) {
            menuItem.target = self
        }
        statusMenu = menu
        statusItem = item
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            if let button = statusItem?.button, let menu = statusMenu {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
            }
        } else {
            // Clic gauche : presse-papier dans l'encoche, prêt à coller.
            notchController?.viewModel.openClipboard()
        }
    }

    @objc private func openAbout() {
        if aboutWindow == nil { aboutWindow = AboutWindowController() }
        aboutWindow?.show()
    }

    /// Ouvre les réglages sur une vérification fraîche : c'est l'onglet
    /// « Mise à jour » qui affiche le résultat.
    @objc private func openUpdates() {
        updater.check()
        openSettings()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Le sélecteur a changé selon les versions de macOS : on tente les deux.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    /// Accès fiable au presse-papier depuis le menu, indépendant du raccourci
    /// clavier global (qui peut échouer si la combinaison est déjà prise).
    @objc private func openClipboardWindow() {
        clipboardWindow?.show()
    }

    @objc private func screenParametersChanged() {
        notchController?.showOnActiveScreen()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
}
