import SwiftUI

/// Mini calendrier mensuel navigable, à gauche du panneau Agenda. Flèches pour
/// changer de mois (« le premier lundi d'octobre » se trouve en deux clics),
/// clic sur le nom du mois pour revenir à aujourd'hui. Aujourd'hui en pastille
/// blanche, un point sous les jours qui ont au moins un évènement.
struct MiniCalendarView: View {
    @ObservedObject var calendar: CalendarProvider
    /// Appelé après la sélection d'un jour (l'accueil s'en sert pour basculer
    /// sur l'onglet Agenda, déjà positionné sur ce jour).
    var onPickDay: (() -> Void)?

    /// Premier jour du mois affiché.
    @State private var displayedMonth: Date = Date()
    /// Jours du mois affiché ayant un évènement — rechargé au changement de mois,
    /// pas à chaque passe de rendu (requête EventKit).
    @State private var eventDays: Set<Int> = []

    /// Semaine française : lundi en premier.
    private static var cal: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private static let weekdaySymbols = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        VStack(spacing: 3) {
            header
            weekdayRow
            dayGrid
        }
        .frame(width: 126)
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(spacing: 2) {
            navButton("chevron.left") { shiftMonth(-1) }
            Spacer(minLength: 0)
            Button {
                displayedMonth = Date()
                reload()
            } label: {
                Text(Self.monthFormatter.string(from: displayedMonth).capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.plain)
            .help("Revenir à aujourd'hui")
            Spacer(minLength: 0)
            navButton("chevron.right") { shiftMonth(1) }
        }
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let cells = monthCells()
        return VStack(spacing: 1) {
            ForEach(0..<cells.count / 7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        dayCell(cells[row * 7 + col])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int?) -> some View {
        if let day {
            let today = isToday(day)
            let selected = isSelected(day)
            Button {
                pick(day)
            } label: {
                Text("\(day)")
                    .font(.system(size: 9, weight: today || selected ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(
                        selected ? Color.black.opacity(0.9)
                        : today ? Color.black.opacity(0.85)
                        : .white.opacity(0.9)
                    )
                    .frame(width: 15, height: 13)
                    // Sélection = pastille orange (prioritaire), aujourd'hui = blanche.
                    .background(
                        selected ? Circle().fill(Color.orange).frame(width: 13, height: 13)
                        : today ? Circle().fill(.white).frame(width: 13, height: 13)
                        : nil
                    )
                    // Point d'évènement en surimpression (pas empilé : la grille
                    // doit rester compacte pour tenir dans la carte).
                    .overlay(alignment: .bottom) {
                        Circle()
                            .fill(eventDays.contains(day) && !today && !selected ? Color.orange : .clear)
                            .frame(width: 3, height: 3)
                            .offset(y: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 13)
        }
    }

    // MARK: Sélection

    private func date(for day: Int) -> Date? {
        var comps = Self.cal.dateComponents([.year, .month], from: displayedMonth)
        comps.day = day
        return Self.cal.date(from: comps)
    }

    private func isSelected(_ day: Int) -> Bool {
        guard let browsed = calendar.browsedDate, let date = date(for: day) else { return false }
        return Self.cal.isDate(browsed, inSameDayAs: date)
    }

    private func pick(_ day: Int) {
        guard let date = date(for: day) else { return }
        if isSelected(day) {
            calendar.browse(nil) // re-clic = désélection
        } else {
            calendar.browse(date)
            onPickDay?()
        }
    }

    // MARK: Géométrie du mois

    /// 35 ou 42 cases (5-6 semaines) : nil pour les cases hors du mois.
    private func monthCells() -> [Int?] {
        let cal = Self.cal
        guard let interval = cal.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let dayCount = cal.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
        // Décalage du 1er du mois par rapport au lundi (0 = lundi).
        let weekday = cal.component(.weekday, from: interval.start)
        let leading = (weekday - cal.firstWeekday + 7) % 7

        var cells: [Int?] = Array(repeating: nil, count: leading)
        cells += (1...dayCount).map { $0 }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func isToday(_ day: Int) -> Bool {
        let cal = Self.cal
        return cal.isDate(Date(), equalTo: displayedMonth, toGranularity: .month)
            && cal.component(.day, from: Date()) == day
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = Self.cal.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = next
        reload()
    }

    private func reload() {
        eventDays = calendar.eventDays(inMonthOf: displayedMonth)
    }
}
