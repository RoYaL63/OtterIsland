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

/// Ce qu'on affiche pour un assistant.
struct AIUsageSnapshot: Equatable {
    var today = TokenCount()
    /// Session la plus récente (fichier modifié en dernier).
    var sessionTokens = TokenCount()
    var sessionProject: String?
    var lastActivity: Date?

    /// Actif = écrit dans les 5 dernières minutes.
    var isActive: Bool {
        guard let lastActivity else { return false }
        return Date().timeIntervalSince(lastActivity) < 5 * 60
    }
}

/// Lit les journaux de session de façon incrémentale : à chaque passage, on ne
/// relit que ce qui a été ajouté à chaque fichier depuis la fois précédente.
/// Un journal Claude Code fait vite plusieurs Mo ; tout relire toutes les
/// 20 s serait gâcher de la batterie.
actor AIUsageReader {
    private struct FileState {
        var offset: UInt64 = 0
        var tokens = TokenCount()       // toute la session (ce fichier)
        var todayTokens = TokenCount()  // la part datée d'aujourd'hui
        var cwd: String?
        /// Codex : compteur cumulé, on garde le dernier vu.
        var codexLastTotal: TokenCount?
        var codexTotalBeforeToday: TokenCount?
    }

    private var files: [String: FileState] = [:]
    /// Claude Code répète une même réponse sur plusieurs lignes (une par bloc
    /// de contenu), avec le même compteur : dédoublonnage par identifiant de
    /// message, sinon les totaux sont plus que doublés.
    private var seenClaudeMessages: Set<String> = []
    private var day = Calendar.current.startOfDay(for: Date())

    func snapshot(for assistant: AIAssistant) -> AIUsageSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        if today != day {
            // Nouveau jour : on recompte tout depuis le début des fichiers.
            day = today
            files.removeAll()
            seenClaudeMessages.removeAll()
        }

        var snapshot = AIUsageSnapshot()
        var latest: (date: Date, path: String)?
        for (url, modified) in recentFiles(in: assistant.logsURL) {
            let path = url.path
            var state = files[path] ?? FileState()
            read(url, into: &state, assistant: assistant)
            files[path] = state
            snapshot.today = snapshot.today + todayTokens(state, assistant: assistant)
            // La session affichée est la principale, pas un sous-agent.
            if !path.contains("/subagents/"), latest == nil || modified > latest!.date {
                latest = (modified, path)
            }
        }
        if let latest, let state = files[latest.path] {
            snapshot.lastActivity = latest.date
            snapshot.sessionTokens = assistant == .codex ? (state.codexLastTotal ?? TokenCount()) : state.tokens
            snapshot.sessionProject = state.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        }
        return snapshot
    }

    private func todayTokens(_ state: FileState, assistant: AIAssistant) -> TokenCount {
        guard assistant == .codex else { return state.todayTokens }
        // Codex publie un total cumulé : la part du jour est la différence
        // entre le dernier total et celui d'avant minuit.
        guard let last = state.codexLastTotal else { return TokenCount() }
        let before = state.codexTotalBeforeToday ?? TokenCount()
        return TokenCount(input: max(0, last.input - before.input),
                          output: max(0, last.output - before.output),
                          cached: max(0, last.cached - before.cached))
    }

    /// Journaux modifiés aujourd'hui (les autres n'ont rien à apporter).
    private func recentFiles(in root: URL) -> [(URL, Date)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return [] }
        var result: [(URL, Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= day else { continue }
            result.append((url, modified))
        }
        return result
    }

    private func read(_ url: URL, into state: inout FileState, assistant: AIAssistant) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return }
        // On ne traite que des lignes complètes : la dernière peut être en
        // cours d'écriture, elle sera lue au prochain passage.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNewline]
        state.offset += UInt64(complete.count)

        for line in complete.split(separator: UInt8(ascii: "\n")) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            switch assistant {
            case .claudeCode: readClaude(object, into: &state)
            case .codex: readCodex(object, into: &state)
            }
        }
    }

    // MARK: Claude Code

    private func readClaude(_ line: [String: Any], into state: inout FileState) {
        if let cwd = line["cwd"] as? String { state.cwd = cwd }
        guard line["type"] as? String == "assistant",
              let message = line["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return }
        if let id = message["id"] as? String {
            guard seenClaudeMessages.insert(id).inserted else { return }
        }
        let tokens = TokenCount(
            input: usage["input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            cached: (usage["cache_read_input_tokens"] as? Int ?? 0) + (usage["cache_creation_input_tokens"] as? Int ?? 0)
        )
        state.tokens = state.tokens + tokens
        if let stamp = line["timestamp"] as? String, let date = Self.parseDate(stamp), date >= day {
            state.todayTokens = state.todayTokens + tokens
        }
    }

    // MARK: Codex
    // Format d'après la documentation de Codex CLI (rollout-*.jsonl) : non
    // vérifié sur une installation réelle. Lecture tolérante : on cherche
    // `total_token_usage` où qu'il soit.

    private func readCodex(_ line: [String: Any], into state: inout FileState) {
        let payload = line["payload"] as? [String: Any] ?? line
        if let cwd = payload["cwd"] as? String { state.cwd = cwd }
        guard let usage = Self.findTotalUsage(in: payload) else { return }
        let input = usage["input_tokens"] as? Int ?? 0
        let cached = usage["cached_input_tokens"] as? Int ?? 0
        let output = (usage["output_tokens"] as? Int ?? 0) + (usage["reasoning_output_tokens"] as? Int ?? 0)
        // Chez Codex, l'entrée INCLUT le cache : on l'en retire.
        let total = TokenCount(input: max(0, input - cached), output: output, cached: cached)
        if let stamp = line["timestamp"] as? String, let date = Self.parseDate(stamp), date < day {
            state.codexTotalBeforeToday = total
        }
        state.codexLastTotal = total
    }

    private static func findTotalUsage(in object: [String: Any]) -> [String: Any]? {
        if let usage = object["total_token_usage"] as? [String: Any] { return usage }
        for value in object.values {
            if let nested = value as? [String: Any], let found = findTotalUsage(in: nested) { return found }
        }
        return nil
    }

    private static func parseDate(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain = ISO8601DateFormatter()
}

/// Publie les relevés pour l'interface. Ne lit rien tant qu'aucun assistant
/// n'est activé dans les réglages.
@MainActor
final class AIUsageMonitor: ObservableObject {
    @Published private(set) var snapshots: [AIAssistant: AIUsageSnapshot] = [:]

    private let reader = AIUsageReader()
    private let settings: OtterSettings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: OtterSettings) {
        self.settings = settings
    }

    func start() {
        Publishers.CombineLatest(settings.$aiClaudeCodeEnabled, settings.$aiCodexEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reschedule() }
            .store(in: &cancellables)
    }

    /// Relevé immédiat (ouverture de l'onglet IA).
    func refresh() {
        let enabled = settings.enabledAssistants
        guard !enabled.isEmpty else {
            snapshots = [:]
            return
        }
        let reader = self.reader
        Task {
            var result: [AIAssistant: AIUsageSnapshot] = [:]
            for assistant in enabled where assistant.isInstalled {
                result[assistant] = await reader.snapshot(for: assistant)
            }
            if result != self.snapshots { self.snapshots = result }
        }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        refresh()
        guard !settings.enabledAssistants.isEmpty else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
