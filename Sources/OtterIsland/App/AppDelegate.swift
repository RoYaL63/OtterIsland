import AppKit

/// Monte la fenêtre d'encoche, un item de barre d'état, et garde les providers en vie.
/// Tout ici tourne sur le thread principal (AppKit, NSPanel) : @MainActor lève
/// l'ambiguïté d'isolation d'acteur avec NotchWindowController.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = OtterSettings()
    private var notchController: NotchWindowController?
    private var clipboardWindow: ClipboardWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent : ni Dock ni menu principal.
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchWindowController(settings: settings)
        controller.showOnActiveScreen()
        notchController = controller
        clipboardWindow = ClipboardWindowController(clipboard: controller.viewModel.clipboard)

        setupStatusItem()

        // Repositionner quand l'agencement d'écran change (résolution, écran externe).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🦦"

        let menu = NSMenu()
        menu.addItem(withTitle: "Presse-papier…", action: #selector(openClipboardWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Réglages OtterIsland…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter OtterIsland", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action == #selector(openSettings) || menuItem.action == #selector(openClipboardWindow) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
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
