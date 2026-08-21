import AppKit
import SwiftUI

/// Crée le panneau, l'héberge une vue SwiftUI et le recale à chaque changement d'écran.
@MainActor
final class NotchWindowController {
    private let settings: OtterSettings
    let viewModel: NotchViewModel
    private var window: NotchWindow?
    private let gestures: GestureController
    private var clipboardHotKey: HotKey?

    /// Marge autour de l'encoche pour laisser respirer la carte étendue et la loutre.
    private let panelWidth: CGFloat = 720
    private let panelHeight: CGFloat = 340

    /// Suivi souris pour le clic-à-travers. Historique des trois approches :
    /// 1. Transparence SwiftUI seule → la zone invisible 720×340 bloquait des
    ///    clics destinés aux autres apps (bug d'origine).
    /// 2. `allowsHitTesting` déclaratif → un parent désactivé l'emporte sur ses
    ///    descendants, le survol mourait entièrement.
    /// 3. Redimensionnement dynamique du panneau AppKit → boucle de rétroaction
    ///    resize ↔ survol, plantage.
    /// Approche 4 (celle-ci) : la fenêtre garde sa taille fixe mais passe en
    /// `ignoresMouseEvents = true` quand l'encoche est repliée — le système
    /// route alors TOUS les événements aux fenêtres du dessous, garanti, sans
    /// dépendre de la transparence. Un timer léger (12 Hz, une comparaison de
    /// rect) surveille le pointeur : entré dans la zone encoche → on réactive
    /// les événements et on déplie. La fenêtre ne bouge jamais, le survol
    /// SwiftUI reste fonctionnel une fois dépliée.
    private var mouseTimer: Timer?
    /// Nombre de ticks consécutifs avec le pointeur ARRÊTÉ dans l'encoche.
    private var hoverTicks = 0
    /// Position du pointeur au tick précédent, pour distinguer « il s'arrête
    /// ici » de « il passe par là ».
    private var lastMouse: NSPoint = .zero
    /// Le pointeur est-il ressorti de la zone chaude depuis la dernière
    /// fermeture ? Tant que non, aucune réouverture n'est possible.
    private var hasExitedSinceClose = true
    /// État déplié du tick précédent, pour détecter la fermeture.
    private var wasExpanded = false
    /// Le repli automatique n'est « armé » qu'une fois le pointeur entré dans la
    /// carte étendue. Sinon une ouverture programmatique (raccourci presse-papier,
    /// verrouillage nettoyage) serait repliée au tick suivant, souris ailleurs.
    private var hoverArmed = false

    init(settings: OtterSettings) {
        self.settings = settings
        let viewModel = NotchViewModel(settings: settings)
        self.viewModel = viewModel
        self.gestures = GestureController(viewModel: viewModel)
        if settings.gestureControl {
            gestures.start()
        }
        if settings.clipboardEnabled {
            installClipboardHotKey(viewModel: viewModel)
        }
    }

    private func installClipboardHotKey(viewModel: NotchViewModel) {
        let hotKey = HotKey(
            keyCode: UInt32(settings.clipboardHotKeyCode),
            modifiers: UInt32(settings.clipboardHotKeyModifiers)
        ) { [weak viewModel] in
            MainActor.assumeIsolated {
                viewModel?.openClipboard()
            }
        }
        clipboardHotKey = hotKey
        settings.clipboardHotKeyRegistrationFailed = !hotKey.isRegistered
    }

    func showOnActiveScreen() {
        guard let screen = NotchMetrics.activeScreen() else { return }
        let screenID = ScreenIdentifier.stableID(for: screen)
        let metrics = NotchMetrics.current(
            for: screen,
            widthOffset: CGFloat(settings.widthOffset(for: screenID))
        )
        viewModel.metrics = metrics
        viewModel.currentScreenID = screenID

        let rect = panelFrame(for: metrics)
        let win = window ?? makeWindow(rect: rect)
        win.setFrame(rect, display: true)
        win.orderFrontRegardless()
        window = win
        startMouseTracking()
    }

    // MARK: Suivi souris / clic-à-travers

    /// Cadence du suivi souris. Partagée avec le calcul du temps d'arrêt exigé.
    private static let tickInterval: TimeInterval = 0.08

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        // Timer planifié sur le main run loop → tire sur le main thread,
        // l'assumeIsolated est donc sûr (même schéma que HotKey).
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickMouse() }
        }
        // .common : continue de tirer pendant les drags et les menus.
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func tickMouse() {
        guard let window, let metrics = viewModel.metrics else { return }
        let mouse = NSEvent.mouseLocation
        defer { lastMouse = mouse }

        // Toute fermeture, d'où qu'elle vienne, ré-arme la garde : il faudra
        // ressortir de la zone avant de pouvoir rouvrir. Sans ça, un pointeur
        // resté sur l'encoche pendant que la carte se referme relance
        // immédiatement l'ouverture — l'île « clignote ».
        if wasExpanded && !viewModel.isExpanded {
            hasExitedSinceClose = false
            hoverTicks = 0
        }
        wasExpanded = viewModel.isExpanded

        if viewModel.isExpanded {
            setIgnoresMouse(false, on: window)
            let inside = expandedIslandRect(metrics).insetBy(dx: -12, dy: -12).contains(mouse)
            if inside {
                hoverArmed = true
            } else if hoverArmed {
                // Filet de sécurité : si le onHover SwiftUI a raté la sortie
                // (drag, animation), on replie dès que le pointeur est loin.
                hoverArmed = false
                hoverTicks = 0
                viewModel.setExpanded(false)
            }
            return
        }

        hoverArmed = false
        // Repliée : la fenêtre laisse tout passer, SAUF si l'aperçu de
        // capture d'écran (cliquable) est affiché sous l'encoche.
        let needsClicks = viewModel.screenshotPreview != nil
        // Zone chaude prolongée AU-DESSUS du bord d'écran : pointeur plaqué en
        // haut, mouseLocation.y vaut maxY, que `contains` exclut (borne
        // supérieure ouverte). Plus d'élargissement latéral : la zone colle
        // désormais à l'encoche physique, elle ne déborde plus sur les onglets
        // du navigateur qui vivent juste à côté.
        let notch = metrics.notchRect
        let hotZone = NSRect(
            x: notch.minX, y: notch.minY,
            width: notch.width, height: notch.height + 8
        )

        guard hotZone.contains(mouse) else {
            hasExitedSinceClose = true
            hoverTicks = 0
            setIgnoresMouse(!needsClicks, on: window)
            return
        }

        setIgnoresMouse(!needsClicks, on: window)
        guard settings.hoverToOpen, hasExitedSinceClose else { return }

        // Le critère n'est pas « depuis combien de temps le pointeur est dans la
        // zone » mais « depuis combien de temps il y est IMMOBILE ». Traverser
        // l'encoche pour aller cliquer un onglet du navigateur remet le compteur
        // à zéro à chaque tick, quelle que soit la lenteur du geste ; s'arrêter
        // dessus, même une demi-seconde, ouvre. C'est la différence entre un
        // passage et une intention.
        let moved = hypot(mouse.x - lastMouse.x, mouse.y - lastMouse.y)
        guard moved <= 4 else {
            hoverTicks = 0
            return
        }

        hoverTicks += 1
        let required = max(1, Int((settings.hoverOpenDelay / Self.tickInterval).rounded()))
        guard hoverTicks >= required else { return }

        hoverTicks = 0
        hoverArmed = true
        setIgnoresMouse(false, on: window)
        viewModel.setExpanded(true)
    }

    /// Évite de re-poser la même valeur 12 fois par seconde au window server.
    private func setIgnoresMouse(_ ignores: Bool, on window: NotchWindow) {
        if window.ignoresMouseEvents != ignores {
            window.ignoresMouseEvents = ignores
        }
    }

    /// Rect écran de la carte étendue (ancrée en haut au centre), même géométrie
    /// que l'île SwiftUI — voir NotchViewModel.expandedSize.
    private func expandedIslandRect(_ metrics: NotchMetrics) -> NSRect {
        let size = viewModel.expandedSize
        return NSRect(
            x: metrics.screenFrame.midX - size.width / 2,
            y: metrics.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func panelFrame(for metrics: NotchMetrics) -> NSRect {
        let x = metrics.screenFrame.midX - panelWidth / 2
        let y = metrics.screenFrame.maxY - panelHeight
        return NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
    }

    private func makeWindow(rect: NSRect) -> NotchWindow {
        let win = NotchWindow(contentRect: rect)
        let root = NotchRootView(viewModel: viewModel)
            .environmentObject(settings)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: rect.size)
        host.autoresizingMask = [.width, .height]
        win.contentView = host
        return win
    }
}
