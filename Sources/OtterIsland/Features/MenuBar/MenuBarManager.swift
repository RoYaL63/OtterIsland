import AppKit
import Combine

/// Plie la barre des menus pour garder de la place.
///
/// Quand une app a un long menu (Chrome, Xcode…) et que l'encoche mange le
/// milieu de la barre, macOS cache SANS PRÉVENIR les icônes de droite qui ne
/// tiennent plus. Ici, l'utilisateur choisit lesquelles peuvent disparaître :
///
///     [icônes à cacher]  │  ‹  🦦  [icônes toujours visibles] [système]
///                        ↑  ↑
///                séparateur  flèche
///
/// Il range avec ⌘-glisser à gauche du séparateur les icônes dont il n'a pas
/// besoin en permanence. Replié, le séparateur s'élargit à 10 000 pt et
/// repousse tout ce qui est à sa gauche hors de l'écran ; un clic sur la
/// flèche les fait revenir. Technique de Hidden Bar et d'Ice : aucune
/// autorisation, marche sur toutes les versions de macOS.
@MainActor
final class MenuBarManager {
    private let settings: OtterSettings
    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private(set) var isCollapsed = false
    private var autoCollapseTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Largeur du séparateur replié : assez pour pousser n'importe quelle
    /// barre hors de l'écran, même sur un écran 6K.
    private static let collapsedLength: CGFloat = 10_000

    init(settings: OtterSettings) {
        self.settings = settings
    }

    func start() {
        settings.$menuBarManagerEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled { self?.install() } else { self?.uninstall() }
            }
            .store(in: &cancellables)
    }

    // MARK: Mise en place

    private func install() {
        guard toggleItem == nil else { return }
        // Ordre de création = ordre d'apparition de droite à gauche : la
        // flèche d'abord (à gauche de la loutre), le séparateur ensuite (à
        // gauche de la flèche). `autosaveName` garde ensuite la place que
        // l'utilisateur leur donne.
        let toggle = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        toggle.autosaveName = "OtterIslandMenuBarToggle"
        toggle.button?.target = self
        toggle.button?.action = #selector(toggleClicked)
        toggle.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        toggleItem = toggle

        let separator = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separator.autosaveName = "OtterIslandMenuBarSeparator"
        separator.button?.title = "│"
        separator.button?.font = .systemFont(ofSize: 13, weight: .ultraLight)
        separator.button?.alphaValue = 0.5
        separator.button?.toolTip = "OtterIsland : glisse avec ⌘ à gauche de ce trait les icônes à cacher"
        separatorItem = separator

        isCollapsed = false
        refreshToggle()
        if settings.menuBarCollapseAtLaunch {
            // Laisse à la barre le temps de placer les items avant de mesurer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.collapse() }
        }
    }

    private func uninstall() {
        autoCollapseTimer?.invalidate()
        if let toggleItem { NSStatusBar.system.removeStatusItem(toggleItem) }
        if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
        toggleItem = nil
        separatorItem = nil
        isCollapsed = false
    }

    // MARK: Plier / déplier

    @objc private func toggleClicked() {
        // Clic droit : le rappel de fonctionnement, plutôt qu'un menu caché.
        if NSApp.currentEvent?.type == .rightMouseUp {
            showHelp()
            return
        }
        isCollapsed ? expand() : collapse()
    }

    /// Bascule depuis l'île ou le menu de la loutre.
    func toggle() {
        guard settings.menuBarManagerEnabled else { return }
        isCollapsed ? expand() : collapse()
    }

    func collapse() {
        guard let separatorItem, !isCollapsed else { return }
        // Garde-fou : si le séparateur est à DROITE de la flèche, l'élargir
        // pousserait la flèche elle-même hors de l'écran — plus moyen de
        // déplier. On refuse et on explique.
        guard separatorIsLeftOfToggle else {
            showMisplacedAlert()
            return
        }
        separatorItem.length = Self.collapsedLength
        separatorItem.button?.title = ""
        isCollapsed = true
        refreshToggle()
    }

    func expand() {
        guard let separatorItem, isCollapsed else { return }
        separatorItem.length = NSStatusItem.variableLength
        separatorItem.button?.title = "│"
        isCollapsed = false
        refreshToggle()
        scheduleAutoCollapse()
    }

    /// Replie tout seul après un délai, pour que la barre reste rangée.
    private func scheduleAutoCollapse() {
        autoCollapseTimer?.invalidate()
        let delay = settings.menuBarAutoCollapseDelay
        guard delay > 0 else { return }
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse() }
        }
    }

    private var separatorIsLeftOfToggle: Bool {
        guard let separatorX = separatorItem?.button?.window?.frame.minX,
              let toggleX = toggleItem?.button?.window?.frame.minX else { return false }
        return separatorX < toggleX
    }

    private func refreshToggle() {
        guard let button = toggleItem?.button else { return }
        // Replié : la flèche pointe vers ce qu'on peut faire réapparaître.
        let symbol = isCollapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isCollapsed ? "Afficher les icônes cachées" : "Cacher les icônes")
        image?.isTemplate = true
        button.image = image?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.toolTip = isCollapsed
            ? "Afficher les icônes cachées (clic droit : mode d'emploi)"
            : "Cacher les icônes à gauche du trait │ (clic droit : mode d'emploi)"
    }

    // MARK: Explications

    private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Plier la barre des menus"
        alert.informativeText = """
        Maintiens ⌘ et glisse, à gauche du trait │, les icônes que tu veux pouvoir cacher. La flèche les cache ou les montre.

        Garde à droite de la flèche les icônes dont tu as toujours besoin : quand une app a un long menu, macOS cache celles qui ne tiennent plus, et ce seront alors les moins utiles.
        """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showMisplacedAlert() {
        let alert = NSAlert()
        alert.messageText = "Le trait │ doit être à gauche de la flèche"
        alert.informativeText = "Sinon, plier la barre cacherait aussi la flèche, et tu ne pourrais plus rien faire réapparaître. Maintiens ⌘ et glisse le trait │ à gauche de la flèche, puis réessaie."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
