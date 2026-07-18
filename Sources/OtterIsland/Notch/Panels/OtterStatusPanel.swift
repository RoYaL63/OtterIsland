import SwiftUI

/// Panneau Loutre : petit mot d'humeur et batterie.
struct OtterStatusPanel: View {
    let mood: OtterMood
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var pomodoro: PomodoroTimer
    let showBattery: Bool

    private var moodLine: String {
        switch mood {
        case .idle: return "Tranquille."
        case .happy: return "En pleine forme, ça charge !"
        case .curious: return "Oh, une demande ?"
        case .playful: return "Coucou, tu veux jouer ?"
        case .swimming: return "Plouf, elle nage sur la musique."
        case .worried: return "Batterie faible, elle se planque…"
        case .sleepy: return "Chut, elle fait la sieste."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OtterIsland")
                .font(.headline)
                .foregroundStyle(.white)
            Text(moodLine)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if showBattery {
                    BatteryBadge(monitor: battery)
                    if let minutes = battery.minutesRemaining {
                        Text(timeText(minutes))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer(minLength: 0)
                pomodoroControl
                quickActions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timeText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }

    private var pomodoroControl: some View {
        Button {
            pomodoro.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: pomodoro.isRunning ? "pause.fill" : "timer")
                    .font(.system(size: 9))
                Text(pomodoro.display)
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Minuteur Pomodoro")
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button { QuickActions.launchClaudeCode() } label: {
                Image(systemName: "terminal.fill").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .help("Lancer Claude Code")
        }
    }
}
