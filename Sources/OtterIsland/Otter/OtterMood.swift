import Foundation

/// Humeur de la loutre, pilotée par le contexte (survol, charge, demande Claude Code, inactivité).
enum OtterMood: String {
    case idle     // au repos, respire doucement
    case happy    // en charge, contente
    case curious  // une demande Claude Code arrive
    case playful  // l'utilisateur ouvre l'encoche
    case swimming // musique en cours
    case worried  // batterie faible, elle se planque
    case sleepy   // inactivité prolongée

    /// Expression du visage associée.
    var face: OtterFace {
        switch self {
        case .idle, .swimming: return .neutral
        case .happy, .playful: return .happy
        case .curious: return .curious
        case .worried: return .worried
        case .sleepy: return .sleepy
        }
    }

    /// Durée d'un cycle de balancement/respiration, en secondes.
    var bobDuration: Double {
        switch self {
        case .idle: return 1.8
        case .happy: return 0.9
        case .curious: return 0.6
        case .playful: return 1.0
        case .swimming: return 1.2
        case .worried: return 0.5
        case .sleepy: return 2.8
        }
    }
}

/// Événement ponctuel joué par la loutre (distinct d'une humeur persistante).
enum OtterEvent {
    case celebrate // elle lance un coquillage en l'air
}

/// Jeton pour déclencher un événement via onChange SwiftUI (l'id force le changement).
struct OtterEventToken: Equatable {
    let id = UUID()
    let event: OtterEvent

    static func == (lhs: OtterEventToken, rhs: OtterEventToken) -> Bool {
        lhs.id == rhs.id
    }
}
