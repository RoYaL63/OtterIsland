import Foundation

/// Onglets de la carte étendue.
/// Ordre = priorité d'usage : presse-papier et captures juste après l'accueil
/// (ce sont les onglets les plus utilisés), miroir en dernier (accessible aussi
/// par la petite icône de l'accueil).
///
/// L'onglet d'accueil s'appelait « Loutre » et portait une patte : il était
/// nommé d'après sa décoration, pas d'après son contenu. Il regroupe les
/// indicateurs, le calendrier et le lecteur — c'est un accueil.
enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case clipboard
    case screenshots
    case monitor
    case music
    case agenda
    case shelf
    case mirror

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .monitor: return "gauge.with.dots.needle.50percent"
        case .music: return "music.note"
        case .agenda: return "calendar"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard"
        case .mirror: return "camera.fill"
        case .screenshots: return "camera.viewfinder"
        }
    }

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .monitor: return "Moniteur"
        case .music: return "Musique"
        case .agenda: return "Agenda"
        case .shelf: return "Étagère"
        case .clipboard: return "Presse-papier"
        case .mirror: return "Miroir"
        case .screenshots: return "Captures"
        }
    }
}

/// Éléments de l'accueil qu'on peut afficher ou masquer
/// (Réglages › Fonctionnalités). La batterie garde son réglage historique,
/// `showBattery`.
enum HomeItem: String, CaseIterable, Identifiable {
    case memory, nextEvent, pomodoro, calendar, music, cleanup, mirror

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: return "Mémoire (RAM)"
        case .nextEvent: return "Prochain rendez-vous"
        case .pomodoro: return "Pomodoro"
        case .calendar: return "Mini calendrier"
        case .music: return "Lecture en cours"
        case .cleanup: return "Bouton Nettoyage du clavier"
        case .mirror: return "Bouton Miroir"
        }
    }

    var icon: String {
        switch self {
        case .memory: return "memorychip"
        case .nextEvent: return "calendar.badge.clock"
        case .pomodoro: return "timer"
        case .calendar: return "calendar"
        case .music: return "music.note"
        case .cleanup: return "sparkles"
        case .mirror: return "camera.fill"
        }
    }
}
