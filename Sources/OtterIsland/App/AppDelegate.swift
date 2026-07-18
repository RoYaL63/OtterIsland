import AppKit

/// Monte la fenêtre d'encoche, un item de barre d'état, et garde les providers en vie.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = OtterSettings()
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent : ni Dock ni menu principal.
        NSApp.setActivationPolicy(.accessory)

        let controller = NotchWindowController(settings: settings)
        controller.showOnActiveScreen()
        notchController = controller

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
        menu.addItem(withTitle: "Réglages OtterIsland…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter OtterIsland", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action == #selector(openSettings) {
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

    @objc private func screenParametersChanged() {
        notchController?.showOnActiveScreen()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }
}
