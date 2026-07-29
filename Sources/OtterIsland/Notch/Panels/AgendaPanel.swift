import SwiftUI
import AppKit

/// Panneau Agenda : prochains évènements et rappels (rempli par CalendarProvider).
struct AgendaPanel: View {
    @ObservedObject var calendar: CalendarProvider

    var body: some View {
        Group {
            if !calendar.hasAccess {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agenda non autorisé")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Button("Autoriser") { calendar.requestAccess() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            } else {
                // Mini calendrier navigable à gauche, prochains RDV/rappels à
                // droite. Les évènements terminés sortent de la liste (fenêtre
                // glissante rechargée par le provider).
                HStack(alignment: .top, spacing: 10) {
                    MiniCalendarView(calendar: calendar)
                    Rectangle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        if calendar.events.isEmpty && calendar.reminders.isEmpty {
                            Text("Rien de prévu 🎉")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            ForEach(calendar.events.prefix(3)) { event in
                                eventRow(event)
                            }
                            ForEach(calendar.reminders.prefix(2)) { reminder in
                                reminderRow(reminder)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reminderRow(_ reminder: AgendaReminder) -> some View {
        HStack(spacing: 6) {
            Button {
                calendar.complete(reminder.id)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Marquer comme fait")
            Text(reminder.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(reminder.dueText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Cliquable si un lien de visio est associé : l'ouvre directement.
    private func eventRow(_ event: AgendaEvent) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: event.meetingURL != nil ? "video.fill" : "calendar")
                .font(.system(size: 9))
                .foregroundStyle(event.color)
            Text(event.title)
                .font(.caption.weight(.medium))
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
}
