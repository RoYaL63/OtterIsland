import SwiftUI
import AppKit

/// Panneau d'accueil : trois modules groupés, façon Centre de contrôle.
/// ┌──────────────────────┐ ┌────────────────┐
/// │ indicateurs système  │ │ mini calendrier│
/// │ (RAM, batterie, RDV) │ │   navigable    │
/// └──────────────────────┘ └────────────────┘
/// ┌───────────────────────────────────────┐
/// │ lecteur musique     [nettoyage][miroir]│
/// └───────────────────────────────────────┘
/// Ce qui séparait ces trois blocs était un filet vertical et un filet
/// horizontal ; ce sont maintenant des tuiles de verre distinctes. Un trait dit
/// « ça s'arrête ici » ; une tuile dit « ceci est un objet » — et c'est la
/// grammaire du système, du Centre de contrôle aux réglages.
/// La loutre reste à gauche de la carte et sert d'indicateur vivant façon
/// RunCat : nage = musique, halètement = RAM saturée, chiffon = nettoyage…
///
/// Les quatre indicateurs passent par `OtterStatRow` : icône alignée sur la
/// même colonne, libellé secondaire, valeur à droite. Avant, chacun était écrit
/// à la main avec ses propres tailles et espacements, et la colonne d'icônes
/// n'était pas droite.
struct OtterStatusPanel: View {
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var calendar: CalendarProvider
    @ObservedObject var nowPlaying: AppleScriptNowPlaying
    @ObservedObject var memory: MemoryMonitor
    let showBattery: Bool
    let onToggleCleanup: () -> Void
    let onOpenMirror: () -> Void
    /// Clic sur un jour du mini calendrier : bascule sur l'onglet Agenda,
    /// déjà positionné sur ce jour.
    let onOpenAgenda: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // fixedSize vertical : la rangée prend la hauteur du plus grand des
            // deux modules (le calendrier), et l'autre s'étire pour l'égaler —
            // deux tuiles côte à côte de hauteurs différentes se lisent comme
            // un défaut d'alignement.
            HStack(alignment: .top, spacing: 8) {
                OtterTile {
                    statsColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                OtterTile {
                    MiniCalendarView(calendar: calendar, onPickDay: onOpenAgenda)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            OtterTile(verticalPadding: 6) {
                HStack(alignment: .center, spacing: 8) {
                    musicRow
                    Spacer(minLength: 6)
                    OtterIconButton(
                        icon: "sparkles",
                        tint: Otter.accent,
                        help: "Verrouiller le clavier pour nettoyer",
                        action: onToggleCleanup
                    )
                    OtterIconButton(
                        icon: "camera.fill",
                        help: "Mode miroir (caméra)",
                        action: onOpenMirror
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Colonne indicateurs

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            memoryRow
            if showBattery {
                batteryRow
            }
            if let event = calendar.events.first {
                nextEventRow(event)
            }
            pomodoroControl
        }
    }

    /// RAM façon RunCat : pourcentage + couleur selon la pression système.
    private var memoryRow: some View {
        OtterStatRow(
            icon: "memorychip",
            iconTint: memoryColor,
            label: "RAM",
            progress: memory.usedFraction,
            progressTint: memoryMeterColor
        ) {
            Text("\(Int(memory.usedFraction * 100)) %")
                .font(.otterValue)
                .foregroundStyle(memoryColor)
        }
    }

    /// La jauge ne passe en couleur d'alerte que quand il y a une alerte ; le
    /// reste du temps elle est aqua, pas blanche.
    private var memoryMeterColor: Color {
        memoryColor == Otter.textPrimary ? Otter.accent : memoryColor
    }

    private var batteryMeterColor: Color {
        batteryTint == Otter.textPrimary ? Otter.accent : batteryTint
    }

    private var memoryColor: Color {
        switch memory.pressure {
        case .normal: return memory.usedFraction > 0.85 ? Otter.warning : Otter.textPrimary
        case .warning: return Otter.warning
        case .critical: return Otter.danger
        }
    }

    private var batteryRow: some View {
        OtterStatRow(
            icon: batteryIcon,
            iconTint: batteryTint,
            label: "Batterie",
            progress: Double(battery.percentage) / 100,
            progressTint: batteryMeterColor
        ) {
            HStack(spacing: 6) {
                // `minutesRemaining` vaut 0 tant qu'IOKit calcule encore (et sur
                // secteur) : afficher « 0 min » à ce moment-là fait croire à une
                // batterie à plat.
                if let minutes = battery.minutesRemaining, minutes > 0 {
                    Text(timeText(minutes))
                        .font(.otterMeta)
                        .foregroundStyle(Otter.textSecondary)
                }
                Text("\(battery.percentage) %")
                    .font(.otterValue)
                    .foregroundStyle(batteryTint)
            }
        }
    }

    private var batteryIcon: String {
        if battery.isCharging { return "battery.100.bolt" }
        switch battery.percentage {
        case ...10: return "battery.0"
        case ...35: return "battery.25"
        case ...60: return "battery.50"
        case ...85: return "battery.75"
        default: return "battery.100"
        }
    }

    private var batteryTint: Color {
        if battery.isCharging { return Otter.positive }
        return battery.percentage <= 15 ? Otter.danger : Otter.textPrimary
    }

    /// Prochain évènement du jour, cliquable s'il a un lien de visio.
    private func nextEventRow(_ event: AgendaEvent) -> some View {
        let hasCall = event.meetingURL != nil
        let content = OtterStatRow(
            icon: hasCall ? "video.fill" : "calendar",
            iconTint: hasCall ? Otter.accent : event.color,
            label: event.title
        ) {
            Text(event.timeText)
                .font(.otterMeta)
                .foregroundStyle(Otter.textSecondary)
        }
        return Group {
            if let url = event.meetingURL {
                Button { NSWorkspace.shared.open(url) } label: { content.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help("Rejoindre la visio")
            } else {
                content
            }
        }
    }

    private var pomodoroControl: some View {
        Button {
            pomodoro.toggle()
        } label: {
            OtterStatRow(
                icon: pomodoro.isRunning ? "pause.circle.fill" : "timer",
                iconTint: pomodoro.isRunning ? Otter.accent : Otter.textSecondary,
                label: "Pomodoro"
            ) {
                Text(pomodoro.display)
                    .font(.otterValue)
                    .foregroundStyle(pomodoro.isRunning ? Otter.accent : Otter.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pomodoro.isRunning ? "Mettre le minuteur en pause" : "Démarrer un Pomodoro")
    }

    // MARK: Lecteur

    /// Titre + contrôles. Le titre défile s'il est trop long : avant, il passait
    /// SOUS les boutons (le `scaleEffect` rétrécissait le rendu mais pas la
    /// place réservée, les contrôles débordaient donc sur le texte).
    @ViewBuilder
    private var musicRow: some View {
        if let track = nowPlaying.current {
            HStack(spacing: 8) {
                OtterIconBadge(
                    icon: track.isPlaying ? "waveform" : "pause.fill",
                    tint: track.isPlaying ? Otter.accent : Otter.textSecondary
                )
                MarqueeText(text: "\(track.title) — \(track.artist)", font: .otterBody)
                    .foregroundStyle(Otter.textPrimary)
                MediaControlsView(provider: nowPlaying, size: .compact)
            }
        } else {
            HStack(spacing: 8) {
                OtterIconBadge(icon: "music.note", tint: Otter.textSecondary)
                Text("Rien ne joue")
                    .font(.otterLabel)
                    .foregroundStyle(Otter.textTertiary)
            }
        }
    }

    private func timeText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }
}
