import SwiftUI
import AppKit

/// Panneau Musique : pochette, morceau, barre de progression et contrôles.
struct MusicPanel: View {
    @ObservedObject var provider: AppleScriptNowPlaying
    @ObservedObject var volume: VolumeMonitor
    /// Options affichées : Réglages › Fonctionnalités › Musique.
    @EnvironmentObject private var settings: OtterSettings

    /// Un seul module, comme la tuile « En lecture » du Centre de contrôle :
    /// pochette, morceau, position, transport. Le contenu était posé à nu sur
    /// le verre de l'île — il flottait sans rien qui le rassemble.
    var body: some View {
        OtterTile(horizontalPadding: 12, verticalPadding: 10) {
            VStack(alignment: .leading, spacing: 9) {
                if provider.automationDenied {
                    automationDeniedHint
                } else if let track = provider.current {
                    HStack(spacing: 10) {
                        artwork
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(text: track.title, font: .otterTitle)
                                .foregroundStyle(Otter.textPrimary)
                            MarqueeText(text: track.artist, font: .otterMeta)
                                .foregroundStyle(Otter.textSecondary)
                        }
                    }
                    scrubber(track)
                    // Une seule rangée : volume à gauche, transport au centre,
                    // l'app à droite. Une rangée de plus ne tenait pas dans la
                    // hauteur de la carte.
                    ZStack {
                        MediaControlsView(provider: provider)
                        HStack {
                            if settings.musicShowVolume { volumeControl }
                            Spacer(minLength: 0)
                            if settings.musicShowOpenApp { openAppButton }
                        }
                    }
                } else {
                    OtterEmptyState(
                        icon: "music.note",
                        title: "Rien en lecture",
                        subtitle: "Lance Spotify ou Apple Music, la loutre se met à nager."
                    )
                    if settings.musicShowOpenApp {
                        launchButtons
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Volume et app

    /// Son coupé / rétabli, et volume de la sortie du Mac.
    private var volumeControl: some View {
        HStack(spacing: 4) {
            Button {
                volume.toggleMute()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(volume.isMuted ? Otter.warning : Otter.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!volume.canMute)
            .help(volume.isMuted ? "Rétablir le son" : "Couper le son")
            Slider(
                value: Binding(get: { Double(volume.volume) }, set: { volume.setVolume(Float($0)) }),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(Otter.accent)
            .frame(width: 70)
            .help("Volume du Mac")
        }
    }

    private var volumeIcon: String {
        if volume.isMuted || volume.volume == 0 { return "speaker.slash.fill" }
        if volume.volume < 0.34 { return "speaker.wave.1.fill" }
        if volume.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// Ouvre l'app qui joue (Spotify en priorité, sinon Musique).
    private var openAppButton: some View {
        let app = MusicApps.running ?? MusicApps.installed.first
        return Button {
            if let app { MusicApps.open(app) }
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Otter.textSecondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(app == nil)
        .help(app.map { "Ouvrir \($0.name)" } ?? "Ni Spotify ni Musique ne sont installés")
    }

    /// Rien ne joue : de quoi lancer un lecteur sans quitter l'île.
    private var launchButtons: some View {
        HStack(spacing: 8) {
            ForEach(MusicApps.installed, id: \.bundleID) { app in
                OtterActionLink(title: "Ouvrir \(app.name)", icon: "arrow.up.forward.app", tint: Otter.accent) {
                    MusicApps.open(app)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// macOS refuse l'Automatisation vers Spotify/Music tant qu'elle n'est pas
    /// accordée manuellement : sans ce message, ça ressemble à un bug silencieux.
    private var automationDeniedHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OtterIconBadge(icon: "lock.trianglebadge.exclamationmark", tint: Otter.warning)
                // Couleur dans la pastille, texte en blanc franc : voir
                // AgendaPanel, même règle de vibrance.
                Text("Autorisation requise")
                    .font(.otterBody)
                    .foregroundStyle(Otter.textPrimary)
            }
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
                        .font(.system(size: 16))
                        .foregroundStyle(Otter.textSecondary)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous))
        .overlay(
            SpecularRim(
                shape: RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous),
                strength: 0.8,
                lineWidth: 0.75
            )
        )
        // La pochette est l'objet le plus « matière » du panneau : une ombre
        // courte la décolle du verre au lieu de la coller dessus.
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    private func scrubber(_ track: NowPlayingInfo) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let fraction = track.fraction(at: context.date)
            VStack(spacing: 4) {
                OtterMeter(value: fraction, height: 5)
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

/// Lecteurs pilotés par l'île, et de quoi les ouvrir.
enum MusicApps {
    struct App {
        let name: String
        let bundleID: String
    }

    static let all = [
        App(name: "Spotify", bundleID: "com.spotify.client"),
        App(name: "Musique", bundleID: "com.apple.Music"),
    ]

    static var installed: [App] {
        all.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// Le lecteur ouvert, Spotify d'abord (même priorité que la lecture).
    static var running: App? {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return all.first { ids.contains($0.bundleID) }
    }

    static func open(_ app: App) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
