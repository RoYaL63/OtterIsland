import Foundation
import EventKit
import SwiftUI
import Combine

struct AgendaEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let cgColor: CGColor?
    /// Lien de visio (Meet/Zoom/Teams…) associé, s'il y en a un.
    let meetingURL: URL?

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

    /// Jour choisi dans le mini calendrier (nil = pas de sélection, la liste
    /// affiche les prochains RDV). Partagé entre l'accueil et l'onglet Agenda :
    /// cliquer un jour sur l'accueil ouvre l'Agenda déjà positionné dessus.
    @Published private(set) var browsedDate: Date?
    /// Évènements du jour choisi (journée entière, y compris déjà passés — on
    /// consulte, on ne « rappelle » pas).
    @Published private(set) var browsedEvents: [AgendaEvent] = []

    private let store = EKEventStore()
    private var refreshTimer: Timer?

    func start() {
        requestAccess()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store
        )
        // Rafraîchit périodiquement : les listes étaient chargées au lancement
        // puis seulement sur modification du store — un RDV passé restait donc
        // affiché toute la journée. La fenêtre glissante (start = maintenant)
        // le fait sortir naturellement à chaque relevé.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.hasAccess else { return }
                self.reloadEvents()
                self.reloadReminders()
            }
        }
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

    /// Sélectionne un jour (ou efface la sélection avec nil) et charge ses
    /// évènements. Requête synchrone : une journée, c'est instantané.
    func browse(_ date: Date?) {
        browsedDate = date
        guard let date, hasAccess,
              let interval = Calendar.current.dateInterval(of: .day, for: date) else {
            browsedEvents = []
            return
        }
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil
        )
        browsedEvents = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
            .map {
                AgendaEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "(sans titre)",
                    start: $0.startDate,
                    cgColor: $0.calendar.cgColor,
                    meetingURL: Self.meetingURL(for: $0)
                )
            }
    }

    /// Jours du mois de `date` ayant au moins un évènement (pour les points du
    /// mini calendrier). Requête synchrone EventKit : un mois, c'est instantané.
    func eventDays(inMonthOf date: Date) -> Set<Int> {
        guard hasAccess,
              let interval = Calendar.current.dateInterval(of: .month, for: date) else { return [] }
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: nil
        )
        return Set(store.events(matching: predicate).map {
            Calendar.current.component(.day, from: $0.startDate)
        })
    }

    private func reloadEvents() {
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let mapped = store.events(matching: predicate)
            // Un évènement en cours reste utile ; un évènement TERMINÉ ne
            // s'affiche plus (le prédicat inclut ce qui chevauche la fenêtre).
            .filter { $0.endDate > start }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)
            .map {
                AgendaEvent(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "(sans titre)",
                    start: $0.startDate,
                    cgColor: $0.calendar.cgColor,
                    meetingURL: Self.meetingURL(for: $0)
                )
            }
        events = Array(mapped)
    }

    /// `event.url` porte le lien de visio pour la plupart des évènements Google
    /// Calendar synchronisés. À défaut, on cherche le premier lien http(s) dans
    /// les notes (cas Zoom/Teams collés en texte).
    private static func meetingURL(for event: EKEvent) -> URL? {
        if let url = event.url { return url }
        guard let notes = event.notes else { return nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(notes.startIndex..., in: notes)
        return detector?.firstMatch(in: notes, range: range)?.url
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
