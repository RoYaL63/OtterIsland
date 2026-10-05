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

    init(id: String, title: String, detail: String?, kind: String?, createdAt: Date?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.createdAt = createdAt
    }

    /// Simple notification : rien à approuver, un « OK » suffit.
    var isNotice: Bool { kind == "notice" }

    /// Message brut d'un assistant, relayé par les scripts de
    /// `AIHookInstaller` :
    /// - Claude Code (hook Notification) : `hook_event_name`, `message`, `cwd` ;
    /// - Codex (`notify`) : `type` = `agent-turn-complete`,
    ///   `last-assistant-message`, `cwd`.
    static func fromAssistantMessage(_ data: Data, id: String) -> ActionRequest? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let project = (json["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        if json["hook_event_name"] != nil {
            let message = json["message"] as? String ?? "Claude Code attend ta réponse"
            return ActionRequest(
                id: id,
                title: Self.translateClaude(message),
                detail: project.map { "Claude Code · \($0)" } ?? "Claude Code",
                kind: "notice",
                createdAt: Date()
            )
        }
        if (json["type"] as? String)?.hasPrefix("agent-turn") == true {
            let last = (json["last-assistant-message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ActionRequest(
                id: id,
                title: "Codex a terminé",
                detail: [project.map { "Codex · \($0)" }, last.map { String($0.prefix(140)) }]
                    .compactMap { $0 }.joined(separator: " — "),
                kind: "notice",
                createdAt: Date()
            )
        }
        return nil
    }

    /// Les messages de Claude Code sont en anglais ; les plus courants, en français.
    private static func translateClaude(_ message: String) -> String {
        if message.hasPrefix("Claude needs your permission to use ") {
            return "Claude veut utiliser " + message.dropFirst("Claude needs your permission to use ".count)
        }
        if message.hasPrefix("Claude needs your permission") { return "Claude a besoin de ta permission" }
        if message.hasPrefix("Claude is waiting for your input") { return "Claude attend ta réponse" }
        return message
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
