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
    private var clickThroughTimer: Timer?

    /// Marge autour de l'encoche pour laisser respirer la carte étendue et la loutre.
    private let panelWidth: CGFloat = 720
    private let panelHeight: CGFloat = 340

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
        startClickThroughTracking()
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

    // MARK: Clic-à-travers

    /// Le panneau occupe 720×340 pt en haut de l'écran pour laisser de la place
    /// aux éléments qui débordent de l'encoche (visualiseur audio, HUD, aperçu
    /// capture) : la grande majorité de cette zone doit rester transparente aux
    /// clics. On ne peut pas se fier uniquement à la transparence SwiftUI — sur
    /// certaines configs (écran externe sans encoche réelle notamment), ça peut
    /// laisser une zone morte qui bloque les clics destinés à d'autres apps
    /// (barre de titre, onglets…) même quand rien n'est visible. On recalcule
    /// donc nous-mêmes, à intervalle court, si le curseur est dans la zone
    /// réellement interactive et on bascule `ignoresMouseEvents` en conséquence.
    private func startClickThroughTracking() {
        clickThroughTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateClickThrough() }
        }
    }

    private func updateClickThrough() {
        guard let window, let metrics = viewModel.metrics else { return }
        let mouse = NSEvent.mouseLocation

        // Marge généreuse au-delà de la taille visible : couvre le visualiseur
        // audio (déborde à droite) et le HUD/aperçu capture (débordent en bas).
        let width = viewModel.isExpanded ? 480 : metrics.notchSize.width + 100
        let height = viewModel.isExpanded ? 280 : metrics.notchSize.height + 60
        let interactiveRect = CGRect(
            x: metrics.screenFrame.midX - width / 2,
            y: metrics.screenFrame.maxY - height,
            width: width,
            height: height
        )

        window.ignoresMouseEvents = !interactiveRect.contains(mouse)
    }

    deinit {
        clickThroughTimer?.invalidate()
    }
}
