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
    /// Flèche › des raccourcis : affiche la liste complète.
    var onShowAllShortcuts: () -> Void = {}
    /// « + » quand aucun raccourci n'est épinglé.
    var onAddShortcuts: () -> Void = {}
    /// Éléments affichés : Réglages › Fonctionnalités › Accueil.
    @EnvironmentObject private var settings: OtterSettings

    private func shows(_ item: HomeItem) -> Bool { settings.isHomeItemVisible(item) }

    /// La colonne d'indicateurs a-t-elle au moins une ligne à montrer ?
    private var hasStats: Bool {
        shows(.memory) || showBattery || shows(.pomodoro)
            || (shows(.nextEvent) && calendar.events.first != nil)
    }

    private var hasBottomRow: Bool {
        shows(.music) || shows(.shortcuts) || shows(.cleanup) || showsMirrorButton
    }

    /// Le miroir a déjà son onglet en haut : le bouton de l'accueil ferait
    /// doublon. Il ne revient que si l'onglet est masqué.
    private var showsMirrorButton: Bool {
        shows(.mirror) && !settings.visibleTabs.contains(.mirror)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // fixedSize vertical : la rangée prend la hauteur du plus grand des
            // deux modules (le calendrier), et l'autre s'étire pour l'égaler —
            // deux tuiles côte à côte de hauteurs différentes se lisent comme
            // un défaut d'alignement. Un module masqué laisse toute la largeur
            // à l'autre.
            if hasStats || shows(.calendar) {
                HStack(alignment: .top, spacing: 8) {
                    if hasStats {
                        OtterTile {
                            statsColumn
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                    if shows(.calendar) {
                        OtterTile {
                            MiniCalendarView(calendar: calendar, onPickDay: onOpenAgenda)
                                .frame(maxWidth: hasStats ? nil : .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if hasBottomRow {
                OtterTile(verticalPadding: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        if shows(.music) {
                            musicRow
                        }
                        Spacer(minLength: 6)
                        if shows(.shortcuts) {
                            HomeShortcutsStrip(
                                store: QuickShortcutStore.shared,
                                onShowAll: onShowAllShortcuts,
                                onAdd: onAddShortcuts
                            )
                        }
                        if shows(.cleanup) {
                            OtterIconButton(
                                icon: "keyboard",
                                emoji: "🧹",
                                help: "Verrouiller le clavier pour nettoyer",
                                action: onToggleCleanup
                            )
                        }
                        if showsMirrorButton {
                            OtterIconButton(
                                icon: "camera.fill",
                                help: "Mode miroir (caméra)",
                                action: onOpenMirror
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Colonne indicateurs

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            if shows(.memory) {
                memoryRow
            }
            if showBattery {
                batteryRow
            }
            if shows(.nextEvent), let event = calendar.events.first {
                nextEventRow(event)
            }
            if shows(.pomodoro) {
                pomodoroControl
            }
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

    /// La rangée dit maintenant DANS QUELLE PHASE on est (« Concentration » /
    /// « Pause ») et où en est le décompte : un minuteur qui n'affiche qu'un
    /// nombre oblige à faire le calcul de tête pour savoir s'il reste beaucoup.
    private var pomodoroControl: some View {
        Button {
            pomodoro.toggle()
        } label: {
            OtterStatRow(
                icon: pomodoro.isRunning ? pomodoro.phase.icon : "timer",
                iconTint: pomodoro.isRunning ? Otter.accent : Otter.textSecondary,
                label: pomodoro.phase.label,
                progress: pomodoro.progress,
                progressTint: pomodoro.phase == .rest ? Otter.positive : Otter.accent
            ) {
                Text(pomodoro.display)
                    .font(.otterValue)
                    .foregroundStyle(pomodoro.isRunning ? Otter.accent : Otter.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pomodoro.isRunning
              ? "Mettre en pause (la Concentration se coupe)"
              : "Démarrer une session de \(pomodoro.workMinutes) min")
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

/// Raccourcis en bas de l'accueil : les trois premiers, et une flèche › pour
/// la liste complète. Un « + » s'il n'y en a encore aucun.
private struct HomeShortcutsStrip: View {
    @ObservedObject var store: QuickShortcutStore
    let onShowAll: () -> Void
    let onAdd: () -> Void

    /// Au-delà, le titre du morceau n'aurait plus la place de se lire.
    private let visibleCount = 3

    var body: some View {
        HStack(spacing: 6) {
            if store.items.isEmpty {
                OtterIconButton(icon: "plus", tint: Otter.textSecondary, help: "Épingler des apps, dossiers ou liens", action: onAdd)
            } else {
                ForEach(store.items.prefix(visibleCount)) { item in
                    Button { item.open() } label: {
                        Group {
                            if let icon = item.fileIcon {
                                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Otter.textPrimary)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(Otter.chipFill))
                            }
                        }
                        .frame(width: 26, height: 26)
                        .opacity(item.isMissing ? 0.4 : 1)
                    }
                    .buttonStyle(OtterPressStyle(scale: 0.9))
                    .disabled(item.isMissing)
                    .help(item.title)
                }
                if store.items.count > visibleCount {
                    OtterIconButton(icon: "chevron.right", tint: Otter.textSecondary,
                                    help: "Tous les raccourcis (\(store.items.count))", action: onShowAll)
                }
            }
        }
    }
}
