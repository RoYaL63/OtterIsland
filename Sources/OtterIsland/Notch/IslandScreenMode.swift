import AppKit
import SwiftUI

/// Sur quel écran vit l'île quand plusieurs sont branchés.
///
/// Il n'y a qu'UNE île, qui se déplace d'un écran à l'autre : presse-papier,
/// Pomodoro, Live et loutre restent ainsi un seul état partagé, au lieu d'une
/// copie par écran qui se contredirait.
enum IslandScreenMode: String, CaseIterable, Identifiable {
    /// Toujours le même écran, choisi dans les réglages (l'écran du MacBook par défaut).
    case fixed
    /// L'île saute sur l'écran où se trouve le pointeur.
    case pointer
    /// Un onglet 🦦 sur chaque écran sans encoche ; l'île s'ouvre sur celui
    /// qu'on active.
    case everyScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixed: return "Un écran fixe"
        case .pointer: return "L'écran sous le pointeur"
        case .everyScreen: return "Tous les écrans"
        }
    }

    var detail: String {
        switch self {
        case .fixed:
            return "L'île reste sur l'écran choisi ci-dessus, même si tu travailles sur un autre."
        case .pointer:
            return "L'île suit le pointeur : elle passe sur l'écran où tu te trouves dès qu'elle est repliée."
        case .everyScreen:
            return "Un onglet 🦦 attend en haut de chaque écran sans encoche ; l'île s'ouvre sur celui que tu survoles ou cliques."
        }
    }
}

/// Onglet 🦦 posé en haut au centre d'un écran sans encoche : la poignée de
/// l'île. Même verre que l'île repliée, pour qu'on reconnaisse la même chose.
struct IslandHandleView: View {
    let height: CGFloat

    var body: some View {
        ZStack {
            NotchGlassBackground(topWidth: nil, topHeight: height, bottomRadius: 10, isExpanded: false)
            Text("🦦")
                .font(.system(size: max(11, height * 0.55)))
        }
    }
}

/// Fenêtre de l'onglet 🦦 sur les écrans où l'île n'est pas (mode « Tous les
/// écrans »). Purement visuelle : elle laisse passer la souris. Quand le
/// pointeur arrive dessus, le contrôleur y déplace l'île, qui prend le relais
/// pour le survol et le clic.
final class IslandHandleWindow: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        let host = NSHostingView(rootView: IslandHandleView(height: frame.height))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
