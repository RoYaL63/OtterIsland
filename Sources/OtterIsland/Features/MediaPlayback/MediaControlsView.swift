import SwiftUI

/// Boutons précédent / play-pause / suivant reliés au provider de lecture.
struct MediaControlsView: View {
    @ObservedObject var provider: AppleScriptNowPlaying
    /// `compact` pour la rangée de l'accueil, où la place est comptée.
    var size: Size = .regular

    enum Size {
        case regular, compact

        var symbol: CGFloat { self == .regular ? 14 : 10 }
        var button: CGFloat { self == .regular ? 30 : 20 }
        var spacing: CGFloat { self == .regular ? 10 : 2 }
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            control("backward.fill") { provider.previousTrack() }
            control(provider.current?.isPlaying == true ? "pause.fill" : "play.fill") {
                provider.togglePlayPause()
            }
            control("forward.fill") { provider.nextTrack() }
        }
        // La rangée ne se comprime jamais : c'est le titre qui défile, pas les
        // boutons qui viennent le recouvrir.
        .fixedSize()
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        TransportButton(symbol: symbol, size: size, action: action)
    }
}

/// Un bouton de transport. Séparé pour que chacun porte son propre état de
/// survol : la pastille ne doit s'allumer que sous le curseur.
private struct TransportButton: View {
    let symbol: String
    let size: MediaControlsView.Size
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size.symbol, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size.button, height: size.button)
                .background(
                    Circle()
                        .fill(isHovering ? Otter.tileFillActive : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1)
        .onHover { isHovering = $0 }
        .animation(Otter.hoverMotion, value: isHovering)
        .animation(Otter.selectionMotion, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
