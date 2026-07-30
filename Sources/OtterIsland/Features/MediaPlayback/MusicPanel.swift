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
                        MarqueeText(text: track.title, font: .otterTitle)
                            .foregroundStyle(Otter.textPrimary)
                        MarqueeText(text: track.artist, font: .otterMeta)
                            .foregroundStyle(Otter.textSecondary)
                    }
                }
                scrubber(track)
                HStack {
                    Spacer(minLength: 0)
                    MediaControlsView(provider: provider)
                    Spacer(minLength: 0)
                }
            } else {
                OtterEmptyState(
                    icon: "music.note",
                    title: "Rien en lecture",
                    subtitle: "Lance Spotify ou Apple Music, la loutre se met à nager."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// macOS refuse l'Automatisation vers Spotify/Music tant qu'elle n'est pas
    /// accordée manuellement : sans ce message, ça ressemble à un bug silencieux.
    private var automationDeniedHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Autorisation requise", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.otterBody)
                .foregroundStyle(Otter.warning)
            Text("Réglages Système › Confidentialité et sécurité › Automatisation : autorise OtterIsland pour Spotify, Music et System Events.")
                .font(.otterMeta)
                .foregroundStyle(Otter.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            OtterActionLink(title: "Ouvrir les réglages", icon: "gear", tint: Otter.warning) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
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
                    Otter.chipFill
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(Otter.textSecondary)
                }
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous)
                .stroke(Otter.chipStroke, lineWidth: 0.5)
        )
    }

    private func scrubber(_ track: NowPlayingInfo) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = track.fraction(at: context.date)
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(Otter.accent)
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(timeString(track.position(at: context.date)))
                    Spacer()
                    Text(timeString(track.duration))
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Otter.textSecondary)
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
