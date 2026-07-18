import Foundation

/// Onglets de la carte étendue. La loutre reste à gauche, le panneau change à droite.
enum NotchTab: String, CaseIterable, Identifiable {
    case otter
    case music
    case agenda
    case shelf
    case clipboard
    case mirror

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .otter: return "pawprint.fill"
        case .music: return "music.note"
        case .agenda: return "calendar"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard"
        case .mirror: return "camera.fill"
        }
    }

    var title: String {
        switch self {
        case .otter: return "Loutre"
        case .music: return "Musique"
        case .agenda: return "Agenda"
        case .shelf: return "Étagère"
        case .clipboard: return "Presse-papier"
        case .mirror: return "Miroir"
        }
    }
}
