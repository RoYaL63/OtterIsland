import SwiftUI

/// Petit indicateur "égaliseur" affiché à droite de l'encoche repliée quand de
/// la musique joue. Purement visuel : macOS n'expose pas le niveau audio réel
/// d'une autre app via AppleScript, donc l'animation simule une activité au
/// lieu d'un vrai spectre. Survol → bouton pause/lecture direct.
struct NotchAudioVisualizer: View {
    let isPlaying: Bool
    var onTogglePlayPause: () -> Void

    @State private var isHovering = false

    private let barCount = 3

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { context in
            Group {
                if isHovering {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<barCount, id: \.self) { i in
                            Capsule()
                                .fill(.white.opacity(isPlaying ? 0.9 : 0.35))
                                .frame(width: 2.5, height: barHeight(index: i, date: context.date))
                        }
                    }
                }
            }
        }
        .frame(width: 32, height: 20)
        .contentShape(Rectangle())
        .liquidGlassBackground(in: Capsule(), tint: .black.opacity(0.6))
        .onHover { isHovering = $0 }
        .onTapGesture { onTogglePlayPause() }
        .help(isPlaying ? "Mettre en pause" : "Lecture")
    }

    /// Oscillation lissée (sinusoïde déphasée par barre) plutôt qu'un vrai
    /// niveau audio, inaccessible depuis une autre app en AppleScript.
    private func barHeight(index: Int, date: Date) -> CGFloat {
        guard isPlaying else { return 4 }
        let t = date.timeIntervalSinceReferenceDate
        let phase = Double(index) * 1.7
        let freq = 2.2 + Double(index) * 0.6
        let wave = (sin(t * freq + phase) + 1) / 2
        return 4 + CGFloat(wave) * 11
    }
}
