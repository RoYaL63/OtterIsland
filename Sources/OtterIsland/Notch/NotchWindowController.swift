import AppKit
import SwiftUI

/// Crée le panneau, l'héberge une vue SwiftUI et le recale à chaque changement d'écran.
@MainActor
final class NotchWindowController {
    private let settings: OtterSettings
    private let viewModel: NotchViewModel
    private var window: NotchWindow?
    private let gestures: GestureController
    private var clipboardHotKey: HotKey?

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
            installClipboardHotKey(useCmdV: settings.clipboardUseCmdV, viewModel: viewModel)
        }
    }

    private func installClipboardHotKey(useCmdV: Bool, viewModel: NotchViewModel) {
        let modifiers = useCmdV ? HotKey.cmd : HotKey.cmdShift
        clipboardHotKey = HotKey(keyCode: HotKey.keyV, modifiers: modifiers) { [weak viewModel] in
            MainActor.assumeIsolated {
                viewModel?.openClipboard()
            }
        }
    }

    func showOnActiveScreen() {
        guard let screen = NotchMetrics.activeScreen() else { return }
        let metrics = NotchMetrics.current(
            for: screen,
            widthOffset: CGFloat(settings.notchWidthOffset)
        )
        viewModel.metrics = metrics

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
}
