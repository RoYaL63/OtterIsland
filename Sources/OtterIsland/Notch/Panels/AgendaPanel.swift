import SwiftUI
import AppKit

/// Panneau Agenda : mini calendrier navigable à gauche, prochains RDV et
/// rappels à droite. Les évènements terminés sortent de la liste (fenêtre
/// glissante rechargée par le provider).
struct AgendaPanel: View {
    @ObservedObject var calendar: CalendarProvider

    var body: some View {
        Group {
            if !calendar.hasAccess {
                permissionHint
            } else {
                HStack(alignment: .top, spacing: 12) {
                    MiniCalendarView(calendar: calendar)
                    OtterDivider()
                        .padding(.vertical, 2)
                    list
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var list: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let browsed = calendar.browsedDate {
                // Jour choisi dans le mini calendrier : sa journée entière
                // remplace la liste « à venir ».
                browsedHeader(browsed)
                if calendar.browsedEvents.isEmpty {
                    Text("Rien ce jour-là")
                        .font(.otterLabel)
                        .foregroundStyle(Otter.textTertiary)
                } else {
                    ForEach(calendar.browsedEvents.prefix(4)) { event in
                        eventRow(event)
                    }
                }
            } else if calendar.events.isEmpty && calendar.reminders.isEmpty {
                OtterEmptyState(
                    icon: "checkmark.circle",
                    title: "Rien de prévu",
                    subtitle: "Profites-en."
                )
            } else {
                if !calendar.events.isEmpty {
                    sectionHeader("À venir")
                    ForEach(calendar.events.prefix(3)) { event in
                        eventRow(event)
                    }
                }
                if !calendar.reminders.isEmpty {
                    sectionHeader("Rappels")
                        .padding(.top, 2)
                    ForEach(calendar.reminders.prefix(2)) { reminder in
                        reminderRow(reminder)
                    }
                }
            }
        }
    }

    /// Sépare visuellement RDV et rappels — ils étaient empilés sans rien pour
    /// dire où l'un s'arrêtait et où l'autre commençait.
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.otterMicro)
            .tracking(0.6)
            .foregroundStyle(Otter.textTertiary)
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Agenda non autorisé", systemImage: "calendar.badge.exclamationmark")
                .font(.otterBody)
                .foregroundStyle(Otter.warning)
            Text("OtterIsland a besoin de l'accès Calendrier et Rappels pour afficher ta journée.")
                .font(.otterMeta)
                .foregroundStyle(Otter.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            OtterActionLink(title: "Autoriser", icon: "lock.open", tint: Otter.warning) {
                calendar.requestAccess()
            }
        }
    }

    /// En-tête du jour consulté : « Mar. 6 oct. » + croix pour revenir aux
    /// prochains RDV.
    private func browsedHeader(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Text(Self.dayFormatter.string(from: date).capitalized)
                .font(.otterMicro)
                .tracking(0.6)
                .foregroundStyle(Otter.accent)
            Spacer(minLength: 4)
            Button {
                calendar.browse(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Otter.textTertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Revenir aux prochains rendez-vous")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    private func reminderRow(_ reminder: AgendaReminder) -> some View {
        HStack(spacing: 7) {
            Button {
                calendar.complete(reminder.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Otter.accent)
                    .frame(width: Otter.iconColumn)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Marquer comme fait")
            Text(reminder.title)
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(reminder.dueText)
                .font(.otterMeta)
                .foregroundStyle(Otter.textSecondary)
        }
    }

    /// Cliquable si un lien de visio est associé : l'ouvre directement.
    private func eventRow(_ event: AgendaEvent) -> some View {
        let hasCall = event.meetingURL != nil
        let content = HStack(spacing: 7) {
            // Pastille de la couleur du calendrier : reconnaître « boulot » de
            // « perso » d'un coup d'œil, ce qu'une icône grise uniforme ne
            // permettait pas.
            Group {
                if hasCall {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Otter.accent)
                } else {
                    Circle()
                        .fill(event.color)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: Otter.iconColumn)

            Text(event.title)
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
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
}
