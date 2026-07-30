import SwiftUI

/// Boutons précédent / play-pause / suivant reliés au provider de lecture.
struct MediaControlsView: View {
    @ObservedObject var provider: AppleScriptNowPlaying
    /// `compact` pour la rangée de l'accueil, où la place est comptée.
    var size: Size = .regular

    enum Size {
        case regular, compact

        var symbol: CGFloat { self == .regular ? 13 : 10 }
        var button: CGSize {
            self == .regular ? CGSize(width: 26, height: 22) : CGSize(width: 20, height: 18)
        }
        var spacing: CGFloat { self == .regular ? 16 : 2 }
    }

    var body: some View {
        HStack(spacing: size.spacing) {
            control("backward.fill") { provider.previousTrack() }
            control(provider.current?.isPlaying == true ? "pause.fill" : "play.fill") {
                provider.togglePlayPause()
            }
            control("forward.fill") { provider.nextTrack() }
        }
        .foregroundStyle(.white)
        // La rangée ne se comprime jamais : c'est le titre qui défile, pas les
        // boutons qui viennent le recouvrir.
        .fixedSize()
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size.symbol, weight: .semibold))
                .frame(width: size.button.width, height: size.button.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
