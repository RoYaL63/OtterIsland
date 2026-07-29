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
    /// Nombre de ticks consécutifs avec le pointeur dans l'encoche ; on exige
    /// deux ticks (~160 ms) pour ne pas déplier sur un simple passage de souris.
    private var hoverTicks = 0
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

    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        // Timer planifié sur le main run loop → tire sur le main thread,
        // l'assumeIsolated est donc sûr (même schéma que HotKey).
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickMouse() }
        }
        // .common : continue de tirer pendant les drags et les menus.
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func tickMouse() {
        guard let window, let metrics = viewModel.metrics else { return }
        let mouse = NSEvent.mouseLocation

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
        } else {
            hoverArmed = false
            // Repliée : la fenêtre laisse tout passer, SAUF si l'aperçu de
            // capture d'écran (cliquable) est affiché sous l'encoche.
            let needsClicks = viewModel.screenshotPreview != nil
            // Zone chaude élargie de 4 pt sur les côtés et prolongée AU-DESSUS du
            // bord d'écran : pointeur plaqué en haut, mouseLocation.y vaut maxY,
            // que `contains` exclut (borne supérieure ouverte).
            let notch = metrics.notchRect
            let hotZone = NSRect(
                x: notch.minX - 4, y: notch.minY,
                width: notch.width + 8, height: notch.height + 8
            )
            if hotZone.contains(mouse) {
                hoverTicks += 1
                if hoverTicks >= 2 {
                    hoverTicks = 0
                    hoverArmed = true
                    setIgnoresMouse(false, on: window)
                    viewModel.setExpanded(true)
                }
            } else {
                hoverTicks = 0
                setIgnoresMouse(!needsClicks, on: window)
            }
        }
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
