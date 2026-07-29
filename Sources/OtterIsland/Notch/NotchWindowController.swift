import AppKit
import SwiftUI
import Combine

/// Crée le panneau, l'héberge une vue SwiftUI et le recale à chaque changement d'écran.
@MainActor
final class NotchWindowController {
    private let settings: OtterSettings
    let viewModel: NotchViewModel
    private var window: NotchWindow?
    private let gestures: GestureController
    private var clipboardHotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    /// Le panneau AppKit lui-même est redimensionné selon l'état (pas seulement
    /// le contenu SwiftUI à l'intérieur) : repliée, il ne dépasse la taille de
    /// l'encoche que d'une petite marge (place pour le HUD/aperçu capture qui
    /// débordent légèrement) ; agrandie, il prend la taille de la carte. Un
    /// unique panneau fixe surdimensionné (720×340 pt en permanence) laissait
    /// une zone invisible bloquer les clics destinés à d'autres apps ; compter
    /// sur la seule transparence SwiftUI pour l'éviter s'est montré peu fiable.
    private let collapsedExtraWidth: CGFloat = 40
    private let collapsedExtraHeight: CGFloat = 70
    private let expandedSize = CGSize(width: 480, height: 320)

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

        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateWindowFrame(animated: true)
            }
            .store(in: &cancellables)
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

        let win = window ?? makeWindow()
        window = win
        updateWindowFrame(animated: false)
        win.orderFrontRegardless()
    }

    private func updateWindowFrame(animated: Bool) {
        guard let window, let metrics = viewModel.metrics else { return }
        let size = viewModel.isExpanded
            ? expandedSize
            : CGSize(
                width: metrics.notchSize.width + collapsedExtraWidth,
                height: metrics.notchSize.height + collapsedExtraHeight
            )
        let rect = NSRect(
            x: metrics.screenFrame.midX - size.width / 2,
            y: metrics.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(rect, display: true, animate: animated)
    }

    private func makeWindow() -> NotchWindow {
        let win = NotchWindow(contentRect: .zero)
        let root = NotchRootView(viewModel: viewModel)
            .environmentObject(settings)
        let host = NSHostingView(rootView: root)
        host.autoresizingMask = [.width, .height]
        win.contentView = host
        return win
    }
}
