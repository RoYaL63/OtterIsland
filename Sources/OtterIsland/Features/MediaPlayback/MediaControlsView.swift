import SwiftUI

/// Boutons précédent / play-pause / suivant reliés au provider de lecture.
struct MediaControlsView: View {
    @ObservedObject var provider: AppleScriptNowPlaying

    var body: some View {
        HStack(spacing: 16) {
            control("backward.fill") { provider.previousTrack() }
            control(provider.current?.isPlaying == true ? "pause.fill" : "play.fill") {
                provider.togglePlayPause()
            }
            control("forward.fill") { provider.nextTrack() }
        }
        .foregroundStyle(.white)
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
