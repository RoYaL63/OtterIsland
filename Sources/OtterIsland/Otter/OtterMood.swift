import Foundation

/// Humeur de la loutre, pilotée par le contexte (survol, charge, demande Claude Code, inactivité).
enum OtterMood: String {
    case idle     // au repos, respire doucement
    case happy    // en charge, contente
    case curious  // une demande Claude Code arrive
    case playful  // l'utilisateur ouvre l'encoche
    case swimming // musique en cours
    case worried    // batterie faible, elle se planque
    case sleepy     // inactivité prolongée
    case cleaning   // clavier verrouillé, elle passe un chiffon
    case overloaded // pression mémoire : la RAM sature, elle s'essouffle
    case focused    // Pomodoro en cours : casque sur les oreilles, elle bosse
    case meetingSoon // un RDV commence dans moins de 5 min : elle regarde l'heure
    case night       // il fait nuit et rien ne se passe : lune et bâillements

    /// Expression du visage associée.
    var face: OtterFace {
        switch self {
        case .idle, .swimming, .focused: return .neutral
        case .happy, .playful, .cleaning: return .happy
        case .curious, .meetingSoon: return .curious
        case .worried, .overloaded: return .worried
        case .sleepy, .night: return .sleepy
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
        case .cleaning: return 0.4
        case .overloaded: return 0.35 // respiration courte : elle halète
        case .focused: return 2.4     // ample et régulière : elle est posée
        case .meetingSoon: return 0.7 // un peu pressée
        case .night: return 3.2       // encore plus lente que sleepy
        }
    }
}

/// Événement ponctuel joué par la loutre (distinct d'une humeur persistante).
///
/// Une humeur dit « voilà où on en est » ; un événement dit « ça vient de se
/// passer ». C'est la deuxième catégorie qui rend la loutre vivante : sans
/// elle, rien ne réagit à ce que fait l'utilisateur dans la seconde.
enum OtterEvent {
    case celebrate // elle lance un coquillage en l'air
    case snapshot  // une capture d'écran vient d'être prise
    case caught    // un fichier vient d'être déposé sur l'étagère
    case pomodoroDone // une session de travail est allée au bout
}

/// Jeton pour déclencher un événement via onChange SwiftUI (l'id force le changement).
struct OtterEventToken: Equatable {
    let id = UUID()
    let event: OtterEvent

    static func == (lhs: OtterEventToken, rhs: OtterEventToken) -> Bool {
        lhs.id == rhs.id
    }
}
