import Foundation

/// Une demande d'action déposée par Claude Code dans l'inbox.
/// Format JSON stable pour qu'un hook shell puisse l'écrire sans dépendance.
struct ActionRequest: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String?
    /// Type d'action : "permission", "command", "confirm"... libre côté hook.
    let kind: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, detail, kind, createdAt
    }
}

/// Réponse écrite par OtterIsland dans l'outbox après décision de l'utilisateur.
struct ActionResponse: Codable {
    let id: String
    let approved: Bool
    let respondedAt: Date

    init(id: String, approved: Bool) {
        self.id = id
        self.approved = approved
        self.respondedAt = Date()
    }
}
