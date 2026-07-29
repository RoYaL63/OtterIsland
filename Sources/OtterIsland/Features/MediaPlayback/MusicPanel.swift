import SwiftUI
import AppKit

/// Panneau Musique : pochette, morceau, barre de progression et contrôles.
struct MusicPanel: View {
    @ObservedObject var provider: AppleScriptNowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if provider.automationDenied {
                automationDeniedHint
            } else if let track = provider.current {
                HStack(spacing: 8) {
                    artwork
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                scrubber(track)
                HStack {
                    Spacer(minLength: 0)
                    MediaControlsView(provider: provider)
                    Spacer(minLength: 0)
                }
            } else {
                Text("Rien en lecture")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                Text("Lance Spotify ou Apple Music, la loutre se met à nager.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// macOS refuse l'Automatisation vers Spotify/Music tant qu'elle n'est pas
    /// accordée manuellement : sans ce message, ça ressemble à un bug silencieux.
    private var automationDeniedHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Autorisation requise")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Text("Réglages Système › Confidentialité et sécurité › Automatisation : autorise OtterIsland pour Spotify, Music et System Events.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            Button("Ouvrir les réglages") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = provider.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func scrubber(_ track: NowPlayingInfo) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = track.fraction(at: context.date)
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule()
                            .fill(.white)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(timeString(track.position(at: context.date)))
                    Spacer()
                    Text(timeString(track.duration))
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
