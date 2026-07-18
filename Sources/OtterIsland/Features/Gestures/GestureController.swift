import AppKit

/// Contrôle par geste : molette vers le bas au-dessus de l'encoche pour l'ouvrir,
/// vers le haut pour la fermer. Écoute globale, pas de permission d'accessibilité
/// requise pour la molette.
@MainActor
final class GestureController {
    private let viewModel: NotchViewModel
    private var monitor: Any?

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            let deltaY = event.scrollingDeltaY
            Task { @MainActor in self?.handle(deltaY: deltaY) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(deltaY: CGFloat) {
        guard let metrics = viewModel.metrics else { return }
        // Zone d'activation : l'encoche plus une marge autour.
        let zone = metrics.notchRect.insetBy(dx: -50, dy: -50)
        guard zone.contains(NSEvent.mouseLocation) else { return }

        if deltaY < -1 {
            viewModel.setExpanded(true)
        } else if deltaY > 1 {
            viewModel.setExpanded(false)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
