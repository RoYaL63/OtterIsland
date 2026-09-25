import AppKit
import Combine
import SwiftUI

/// Panneau flottant, en bas à droite de l'écran, qui porte l'aperçu de la
/// dernière capture — séparé de l'encoche pour se comporter comme la vignette
/// de capture de macOS plutôt que comme une excroissance de l'île.
///
/// Il n'existe à l'écran que pendant l'affichage de l'aperçu : le reste du
/// temps il est retiré (`orderOut`), il ne peut donc intercepter aucun clic.
@MainActor
final class ScreenshotToastController {
    private let viewModel: NotchViewModel
    private let settings: OtterSettings
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    /// Marge autour de la carte, pour que son ombre ne soit pas rognée par les
    /// bords du panneau.
    private let shadowPadding: CGFloat = 24
    /// Écart entre la carte et le coin de l'écran (hors Dock et barre des menus).
    private let screenMargin: CGFloat = 12

    init(viewModel: NotchViewModel, settings: OtterSettings) {
        self.viewModel = viewModel
        self.settings = settings
        viewModel.$screenshotPreview
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] visible in
                if visible { self?.show() } else { self?.hide() }
            }
            .store(in: &cancellables)
    }

    private var panelSize: CGSize {
        CGSize(
            width: ScreenshotPreviewView.size.width + shadowPadding * 2,
            height: ScreenshotPreviewView.size.height + shadowPadding * 2
        )
    }

    private func show() {
        hideWork?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel
        if let screen = Self.screenUnderMouse() {
            let visible = screen.visibleFrame
            let size = panelSize
            let origin = NSPoint(
                x: visible.maxX - size.width - screenMargin + shadowPadding,
                y: visible.minY + screenMargin - shadowPadding
            )
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    /// Laisse la transition SwiftUI de sortie se jouer avant de retirer le panneau.
    private func hide() {
        guard let panel else { return }
        panel.ignoresMouseEvents = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.viewModel.screenshotPreview == nil else { return }
            self.panel?.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// La capture est prise là où se trouve le pointeur : c'est sur cet écran
    /// que la notification doit apparaître, pas forcément sur l'écran principal.
    private static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let root = ScreenshotToastRootView(viewModel: viewModel)
            .environmentObject(settings)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: panelSize)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }
}

/// Contenu du panneau : la carte, ancrée en bas à droite, qui glisse depuis le
/// bord droit de l'écran comme une notification système.
private struct ScreenshotToastRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @EnvironmentObject var settings: OtterSettings

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if let shot = viewModel.screenshotPreview {
                ScreenshotPreviewView(
                    shot: shot,
                    didCopy: settings.screenshotAutoCopy,
                    onOpen: { viewModel.openScreenshotPreview() },
                    onDismiss: { viewModel.dismissScreenshotPreview() },
                    onHover: { viewModel.holdScreenshotPreview($0) }
                )
                .id(shot.id)
                .padding(24)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: viewModel.screenshotPreview)
    }
}
