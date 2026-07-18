import SwiftUI

/// Panneau Agenda : prochains évènements et rappels (rempli par CalendarProvider).
struct AgendaPanel: View {
    @ObservedObject var calendar: CalendarProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !calendar.hasAccess {
                Text("Agenda non autorisé")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Button("Autoriser") { calendar.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if calendar.events.isEmpty && calendar.reminders.isEmpty {
                Text("Rien de prévu 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(calendar.events.prefix(2)) { event in
                    row(icon: "calendar", title: event.title, subtitle: event.timeText, color: event.color)
                }
                ForEach(calendar.reminders.prefix(2)) { reminder in
                    reminderRow(reminder)
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
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func row(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
