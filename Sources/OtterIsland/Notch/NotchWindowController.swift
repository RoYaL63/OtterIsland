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
