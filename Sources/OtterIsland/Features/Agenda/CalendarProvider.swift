import Foundation
import EventKit
import SwiftUI
import Combine

struct AgendaEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let cgColor: CGColor?

    var color: Color { cgColor.map { Color($0) } ?? .blue }
    var timeText: String { AgendaFormat.time.string(from: start) }
}

struct AgendaReminder: Identifiable {
    let id: String
    let title: String
    let due: Date?

    var dueText: String {
        guard let due else { return "" }
        return AgendaFormat.time.string(from: due)
    }
}

/// Accès EventKit aux évènements (24 h) et rappels non terminés.
@MainActor
final class CalendarProvider: ObservableObject {
    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var reminders: [AgendaReminder] = []
    @Published private(set) var hasAccess = false

    private let store = EKEventStore()

    func start() {
        requestAccess()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store
        )
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                self?.hasAccess = granted
                if granted { self?.reloadEvents() }
            }
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            Task { @MainActor in
                if granted { self?.reloadReminders() }
            }
        }
    }

    @objc private func storeChanged() {
        reloadEvents()
        reloadReminders()
    }

    /// Coche un rappel depuis l'encoche.
    func complete(_ id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        reloadReminders()
    }

    private func reloadEvents() {
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let mapped = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map {
                AgendaEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "(sans titre)",
                    start: $0.startDate,
                    cgColor: $0.calendar.cgColor
                )
            }
        events = Array(mapped)
    }

    private func reloadReminders() {
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Date())
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: end, calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] items in
            let mapped = (items ?? []).prefix(5).map { item in
                AgendaReminder(
                    id: item.calendarItemIdentifier,
                    title: item.title ?? "(sans titre)",
                    due: item.dueDateComponents?.date
                )
            }
            Task { @MainActor in self?.reminders = Array(mapped) }
        }
    }
}

private enum AgendaFormat {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()
}
