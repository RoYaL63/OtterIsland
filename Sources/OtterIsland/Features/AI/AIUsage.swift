import Foundation
import Combine

/// Assistants de code qu'OtterIsland sait surveiller.
///
/// Les deux écrivent leurs sessions sur le disque, avec les tokens consommés :
/// on les lit, sans réseau ni clé d'API. ChatGPT (l'app) ne laisse rien de
/// lisible, d'où son absence.
enum AIAssistant: String, CaseIterable, Identifiable {
    case claudeCode
    case codex

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var icon: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Dossier des sessions.
    var logsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claudeCode: return home.appendingPathComponent(".claude/projects", isDirectory: true)
        case .codex: return home.appendingPathComponent(".codex/sessions", isDirectory: true)
        }
    }

    var isInstalled: Bool { FileManager.default.fileExists(atPath: logsURL.path) }
}

/// Tokens consommés. `cached` regroupe ce qui a été lu ou écrit dans le cache
/// du modèle : énorme en volume, mais facturé bien moins cher — on le montre à
/// part pour ne pas noyer le reste.
struct TokenCount: Equatable {
    var input = 0
    var output = 0
    var cached = 0

    var total: Int { input + output + cached }

    static func + (a: TokenCount, b: TokenCount) -> TokenCount {
        TokenCount(input: a.input + b.input, output: a.output + b.output, cached: a.cached + b.cached)
    }

    /// 1 234 → « 1,2 k », 3 400 000 → « 3,4 M ».
    static func format(_ value: Int) -> String {
        let v = Double(value)
        switch v {
        case 1_000_000...: return String(format: "%.1f M", v / 1_000_000).replacingOccurrences(of: ".", with: ",")
        case 10_000...: return "\(Int(v / 1000)) k"
        case 1000...: return String(format: "%.1f k", v / 1000).replacingOccurrences(of: ".", with: ",")
        default: return "\(value)"
        }
    }
}

/// Publie les statistiques pour l'interface.
///
/// Rien ne tourne en arrière-plan : on relit les journaux UNIQUEMENT quand
/// l'onglet Assistants IA s'affiche (`refresh`). Le premier relevé lit tout
/// (quelques secondes pour 600 Mo, résultats partiels affichés au fil de
/// l'eau) ; les suivants ne lisent que ce qui a été ajouté depuis.
@MainActor
final class AIUsageMonitor: ObservableObject {
    @Published var snapshots: [AIAssistant: [AIPeriod: AIStatsSnapshot]] = [:]
    @Published private(set) var isRefreshing = false

    private let engine = AIStatsEngine()
    private let settings: OtterSettings
    private var running = false
    private var again = false

    init(settings: OtterSettings) {
        self.settings = settings
    }

    /// Relit les journaux des assistants suivis. Si un relevé est déjà en
    /// cours, un seul de plus est demandé à sa suite.
    func refresh() {
        let enabled = settings.enabledAssistants.filter(\.isInstalled)
        guard !enabled.isEmpty else {
            snapshots = [:]
            return
        }
        guard !running else { again = true; return }
        running = true
        isRefreshing = true
        let engine = self.engine
        Task { @MainActor [weak self] in
            guard let self else { return }
            for assistant in enabled {
                let final = await engine.refresh(assistant: assistant) { [weak self] partial in
                    Task { @MainActor in self?.snapshots[assistant] = partial }
                }
                self.snapshots[assistant] = final
            }
            self.running = false
            self.isRefreshing = false
            if self.again {
                self.again = false
                self.refresh()
            }
        }
    }
}
