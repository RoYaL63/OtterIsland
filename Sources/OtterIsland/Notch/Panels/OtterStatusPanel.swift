import SwiftUI
import AppKit

/// Panneau d'accueil : grille structurée, pas de bavardage.
/// ┌──────────────────────┬────────────────┐
/// │ indicateurs système  │ mini calendrier│
/// │ (RAM, batterie, RDV) │   navigable    │
/// ├──────────────────────┴────────────────┤
/// │ lecteur musique (titre + contrôles)   │
/// │                    [nettoyage][miroir]│
/// └───────────────────────────────────────┘
/// La loutre reste à gauche de la carte et sert d'indicateur vivant façon
/// RunCat : nage = musique, halètement = RAM saturée, chiffon = nettoyage…
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                statsColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                MiniCalendarView(calendar: calendar, onPickDay: onOpenAgenda)
            }

            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 8) {
                musicRow
                Spacer(minLength: 6)
                smallAction(icon: "sparkles", tint: .cyan, help: "Verrouiller le clavier pour nettoyer", action: onToggleCleanup)
                smallAction(icon: "camera.fill", tint: .white.opacity(0.85), help: "Mode miroir (caméra)", action: onOpenMirror)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Colonne indicateurs

    private var statsColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
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
        HStack(spacing: 6) {
            Image(systemName: "memorychip")
                .font(.system(size: 9))
                .foregroundStyle(memoryColor)
                .frame(width: 12)
            Text("RAM")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 4)
            Text("\(Int(memory.usedFraction * 100)) %")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundStyle(memoryColor)
        }
    }

    private var memoryColor: Color {
        switch memory.pressure {
        case .normal: return memory.usedFraction > 0.85 ? .orange : .white.opacity(0.9)
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var batteryRow: some View {
        HStack(spacing: 6) {
            BatteryBadge(monitor: battery)
            Spacer(minLength: 4)
            if let minutes = battery.minutesRemaining {
                Text(timeText(minutes))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    /// Prochain évènement du jour, cliquable s'il a un lien de visio.
    private func nextEventRow(_ event: AgendaEvent) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: event.meetingURL != nil ? "video.fill" : "calendar")
                .font(.system(size: 9))
                .foregroundStyle(event.color)
                .frame(width: 12)
            Text(event.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(event.timeText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        return Group {
            if let url = event.meetingURL {
                Button { NSWorkspace.shared.open(url) } label: { content }
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
            HStack(spacing: 6) {
                Image(systemName: pomodoro.isRunning ? "pause.fill" : "timer")
                    .font(.system(size: 9))
                    .frame(width: 12)
                Text("Pomodoro")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 4)
                Text(pomodoro.display)
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Minuteur Pomodoro")
    }

    // MARK: Lecteur

    @ViewBuilder
    private var musicRow: some View {
        if let track = nowPlaying.current {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.8))
                Text("\(track.title) — \(track.artist)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                MediaControlsView(provider: nowPlaying)
                    .scaleEffect(0.8)
                    .frame(width: 66)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Rien ne joue")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: Petites actions

    private func smallAction(icon: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .chipBackground(in: Circle(), tint: .white.opacity(0.14))
        .help(help)
    }

    private func timeText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }
}
