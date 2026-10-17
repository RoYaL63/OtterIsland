import Foundation

/// Ce qu'on retient d'un journal de session.
struct AIFileAgg {
    /// Octets déjà lus : un nouveau relevé reprend ici.
    var offset: UInt64 = 0
    var cwd: String?
    /// Journal d'un sous-agent : ses tokens comptent, pas comme une conversation.
    var isSubagent = false
    /// Tokens par jour local.
    var tokensByDay: [Int: TokenCount] = [:]
    /// Intervalles d'activité (secondes depuis 1970) : deux évènements à moins
    /// de `idleGap` l'un de l'autre font partie du même.
    var intervals: [(start: Double, end: Double)] = []
    /// Jours locaux où cette session a travaillé.
    var eventDays: Set<Int> = []
    var lastEvent: Double = 0
    /// Derniers identifiants de message vus : Claude Code écrit chaque réponse
    /// sur plusieurs lignes, avec le même compteur.
    var recentIDs: [String] = []
    /// Codex publie un total cumulé : on garde le précédent pour en tirer la part de chaque évènement.
    var lastTotals: TokenCount?

    mutating func record(_ t: Double, gap: Double, day: Int) {
        eventDays.insert(day)
        if t > lastEvent { lastEvent = t }
        if let last = intervals.last, t >= last.start - gap, t - last.end <= gap {
            intervals[intervals.count - 1] = (min(last.start, t), max(last.end, t))
        } else {
            intervals.append((t, t))
        }
    }

    mutating func remember(id: String) -> Bool {
        if recentIDs.contains(id) { return false }
        recentIDs.append(id)
        if recentIDs.count > 64 { recentIDs.removeFirst(recentIDs.count - 64) }
        return true
    }
}

extension TokenCount {
    static func += (a: inout TokenCount, b: TokenCount) { a = a + b }
    /// Différence terme à terme, jamais négative.
    static func - (a: TokenCount, b: TokenCount) -> TokenCount {
        TokenCount(input: max(0, a.input - b.input), output: max(0, a.output - b.output), cached: max(0, a.cached - b.cached))
    }
}

/// Lit les journaux de session des assistants et en tire tokens, temps actif,
/// conversations et projets, par période.
///
/// Pensé pour 600 Mo de journaux : lecture par blocs, ligne repérée sans être
/// décodée (`AILineReader`), reprise à l'octet près d'un relevé au suivant. Le
/// premier relevé lit tout une fois ; les suivants ne lisent que ce qui a été
/// ajouté.
actor AIStatsEngine {
    /// Silence (secondes) au-delà duquel on considère que ça ne travaille plus.
    static let idleGap: Double = 300
    private static let chunk = 8 << 20

    private var aggs: [String: AIFileAgg] = [:]
    private var projectCache: [String: (id: String, root: String)] = [:]
    private var tzOffsetCache: [Int: Int] = [:]

    /// Relit ce qui a changé, puis calcule les trois périodes.
    /// - Parameters:
    ///   - ignoringFilesModifiedAfter: ignore les journaux encore en cours
    ///     d'écriture (utile pour comparer à un calcul indépendant).
    ///   - progress: reçoit des résultats partiels pendant le premier relevé.
    func refresh(
        assistant: AIAssistant,
        now: Date = Date(),
        ignoringFilesModifiedAfter: Date? = nil,
        progress: (@Sendable ([AIPeriod: AIStatsSnapshot]) -> Void)? = nil
    ) -> [AIPeriod: AIStatsSnapshot] {
        let cutoff = Self.rangeStart(days: AIPeriod.month.days, now: now).addingTimeInterval(-86_400)
        let files = Self.journals(in: assistant.logsURL, modifiedSince: cutoff, notAfter: ignoringFilesModifiedAfter)
        var lastPublish = Date()

        for (index, file) in files.enumerated() {
            let key = assistant.rawValue + ":" + file.url.path
            var agg = aggs[key] ?? AIFileAgg(isSubagent: file.url.path.contains("/subagents/"))
            if file.size < agg.offset { agg = AIFileAgg(isSubagent: agg.isSubagent) }   // fichier remplacé
            if file.size > agg.offset { ingest(file.url, into: &agg, assistant: assistant) }
            aggs[key] = agg

            if let progress, index < files.count - 1, Date().timeIntervalSince(lastPublish) > 0.4 {
                lastPublish = Date()
                progress(snapshots(for: assistant, now: now, complete: false))
            }
        }
        return snapshots(for: assistant, now: now, complete: true)
    }

    // MARK: Fichiers

    private struct Journal { let url: URL; let size: UInt64; let modified: Date }

    /// Journaux modifiés depuis `cutoff`, du plus récent au plus ancien.
    private static func journals(in root: URL, modifiedSince cutoff: Date, notAfter limit: Date?) -> [Journal] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        ) else { return [] }
        var result: [Journal] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  v.isRegularFile == true, let modified = v.contentModificationDate, modified >= cutoff
            else { continue }
            if let limit, modified > limit { continue }
            result.append(Journal(url: url, size: UInt64(v.fileSize ?? 0), modified: modified))
        }
        return result.sorted { $0.modified > $1.modified }
    }

    private func ingest(_ url: URL, into agg: inout AIFileAgg, assistant: AIAssistant) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var offset = agg.offset
        while true {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: Self.chunk), !data.isEmpty else { break }
            let consumed: Int = data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                guard let base = bytes.baseAddress else { return 0 }
                // Dernier saut de ligne : au-delà, la ligne est peut-être en cours d'écriture.
                guard let lastNewline = (0..<bytes.count).last(where: { bytes[$0] == 10 }) else {
                    return bytes.count >= Self.chunk ? bytes.count : 0     // ligne géante : on l'abandonne
                }
                var start = 0
                while start <= lastNewline {
                    let remaining = lastNewline - start + 1
                    let nl = memchr(base + start, 10, remaining).map { UnsafePointer<UInt8>($0.assumingMemoryBound(to: UInt8.self)) - base } ?? lastNewline
                    let line = UnsafeBufferPointer(rebasing: bytes[start..<nl])
                    if !line.isEmpty {
                        switch assistant {
                        case .claudeCode: processClaude(line, &agg)
                        case .codex: processCodex(line, &agg)
                        }
                    }
                    start = nl + 1
                }
                return lastNewline + 1
            }
            if consumed == 0 { break }
            offset += UInt64(consumed)
            if data.count < Self.chunk { break }    // fin du fichier
        }
        agg.offset = offset
    }

    // MARK: Lignes

    private func processClaude(_ line: AILineReader.Bytes, _ agg: inout AIFileAgg) {
        let isAssistant = AILineReader.find(line, "\"type\":\"assistant\"") != nil
        guard isAssistant || AILineReader.find(line, "\"type\":\"user\"") != nil,
              let t = AILineReader.timestamp(in: line) else { return }
        if let cwd = AILineReader.string(in: line, key: "\"cwd\":\""), cwd != agg.cwd { agg.cwd = cwd }
        let day = dayIndex(t)
        agg.record(t, gap: Self.idleGap, day: day)
        guard isAssistant else { return }
        if let id = AILineReader.string(in: line, key: "\"id\":\"msg_"), !agg.remember(id: id) { return }
        guard let usage = AILineReader.object(in: line, after: "\"usage\":") else { return }
        func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        agg.tokensByDay[day, default: TokenCount()] += TokenCount(
            input: int("input_tokens"),
            output: int("output_tokens"),
            cached: int("cache_read_input_tokens") + int("cache_creation_input_tokens")
        )
    }

    /// Format d'après la documentation de Codex CLI : non vérifié sur une
    /// installation réelle.
    private func processCodex(_ line: AILineReader.Bytes, _ agg: inout AIFileAgg) {
        guard let t = AILineReader.timestamp(in: line) else { return }
        if agg.cwd == nil, let cwd = AILineReader.string(in: line, key: "\"cwd\":\"") { agg.cwd = cwd }
        let day = dayIndex(t)
        agg.record(t, gap: Self.idleGap, day: day)
        guard let usage = AILineReader.object(in: line, after: "\"total_token_usage\":") else { return }
        func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let cached = int("cached_input_tokens")
        // Chez Codex l'entrée INCLUT le cache, et la sortie inclut le raisonnement.
        let total = TokenCount(input: max(0, int("input_tokens") - cached), output: int("output_tokens"), cached: cached)
        let delta = (agg.lastTotals.map { total.total >= $0.total ? total - $0 : total }) ?? total
        agg.lastTotals = total
        agg.tokensByDay[day, default: TokenCount()] += delta
    }

    // MARK: Jours

    /// Numéro du jour local (jours depuis 1970 dans le fuseau de l'utilisateur).
    func dayIndex(_ t: Double) -> Int {
        let hour = Int(t / 3600)
        let offset: Int
        if let cached = tzOffsetCache[hour] {
            offset = cached
        } else {
            offset = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: Double(hour) * 3600))
            tzOffsetCache[hour] = offset
        }
        return Int(((t + Double(offset)) / 86_400).rounded(.down))
    }

    /// Minuit local du premier jour d'une période de `days` jours finissant aujourd'hui.
    static func rangeStart(days: Int, now: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) ?? now
    }

    // MARK: Projets

    /// Racine du projet : le dossier du dépôt git (on remonte depuis le dossier
    /// de travail), ou le dépôt d'un worktree de Claude Code.
    private func project(for cwd: String?) -> (id: String, root: String) {
        guard let cwd, !cwd.isEmpty else { return ("?", "") }
        if let hit = projectCache[cwd] { return hit }
        var root = cwd
        if let marker = cwd.range(of: "/.claude/worktrees/") {
            root = String(cwd[..<marker.lowerBound])
        } else {
            var dir = cwd
            let home = NSHomeDirectory()
            while dir.count > 1 {
                if FileManager.default.fileExists(atPath: dir + "/.git") { root = dir; break }
                if dir == home { break }
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        let result = (id: root, root: root)
        projectCache[cwd] = result
        return result
    }

    private static func displayName(root: String, others: [String]) -> String {
        if root.isEmpty { return "Sans dossier" }
        if root == NSHomeDirectory() { return "Dossier personnel" }
        let leaf = (root as NSString).lastPathComponent
        // Deux projets de même nom : on ajoute le dossier parent.
        if others.filter({ ($0 as NSString).lastPathComponent == leaf }).count > 1 {
            return ((root as NSString).deletingLastPathComponent as NSString).lastPathComponent + "/" + leaf
        }
        return leaf
    }

    // MARK: Résultats

    func snapshots(for assistant: AIAssistant, now: Date, complete: Bool) -> [AIPeriod: AIStatsSnapshot] {
        let relevant = aggs.filter { $0.key.hasPrefix(assistant.rawValue + ":") }.map(\.value)
        var out: [AIPeriod: AIStatsSnapshot] = [:]
        for period in AIPeriod.allCases {
            out[period] = snapshot(period: period, files: relevant, now: now, complete: complete)
        }
        return out
    }

    private func snapshot(period: AIPeriod, files: [AIFileAgg], now: Date, complete: Bool) -> AIStatsSnapshot {
        let start = Self.rangeStart(days: period.days, now: now)
        let startEpoch = start.timeIntervalSince1970, endEpoch = now.timeIntervalSince1970
        let today = dayIndex(endEpoch)
        let firstDay = today - (period.days - 1)

        var snap = AIStatsSnapshot(period: period, isComplete: complete)
        var byProject: [String: (stat: AIProjectStat, intervals: [(Double, Double)])] = [:]
        var allIntervals: [(Double, Double)] = []
        var newest: (event: Double, project: String)?

        for agg in files where agg.lastEvent >= startEpoch {
            let proj = project(for: agg.cwd)
            var entry = byProject[proj.id] ?? (AIProjectStat(id: proj.id, name: proj.root), [])

            for (day, tokens) in agg.tokensByDay where day >= firstDay && day <= today {
                snap.tokens += tokens
                entry.stat.tokens += tokens
            }
            if !agg.isSubagent, agg.eventDays.contains(where: { $0 >= firstDay && $0 <= today }) {
                snap.sessions += 1
                entry.stat.sessions += 1
            }
            for interval in agg.intervals {
                let s = max(interval.start, startEpoch), e = min(interval.end, endEpoch)
                guard e > s else { continue }
                allIntervals.append((s, e))
                entry.intervals.append((s, e))
            }
            if agg.lastEvent >= startEpoch {
                let date = Date(timeIntervalSince1970: agg.lastEvent)
                if entry.stat.lastActivity.map({ date > $0 }) ?? true { entry.stat.lastActivity = date }
                if !agg.isSubagent, newest == nil || agg.lastEvent > newest!.event { newest = (agg.lastEvent, proj.id) }
            }
            byProject[proj.id] = entry
        }

        let roots = byProject.values.map(\.stat.name)
        var projects: [AIProjectStat] = []
        for (_, value) in byProject {
            var stat = value.stat
            stat.activeSeconds = Self.unionLength(value.intervals)
            stat.name = Self.displayName(root: stat.name, others: roots)
            guard stat.activeSeconds > 0 || stat.tokens.total > 0 else { continue }
            projects.append(stat)
        }
        projects.sort { ($0.activeSeconds, $0.tokens.total) > ($1.activeSeconds, $1.tokens.total) }

        snap.projects = projects
        snap.activeSeconds = Self.unionLength(allIntervals)
        snap.lastActivity = projects.compactMap(\.lastActivity).max()
        if let newest, let current = projects.first(where: { $0.id == newest.project }) { snap.currentProject = current.name }

        // Temps actif de chaque jour : la réunion des intervalles, découpée à minuit local.
        let merged = Self.merge(allIntervals)
        let cal = Calendar.current
        snap.dailyActiveSeconds = (0..<period.days).map { i in
            guard let dayStart = cal.date(byAdding: .day, value: i, to: start),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
            let a = dayStart.timeIntervalSince1970, b = dayEnd.timeIntervalSince1970
            return merged.reduce(0) { $0 + max(0, min($1.1, b) - max($1.0, a)) }
        }
        return snap
    }

    // MARK: Intervalles

    static func merge(_ intervals: [(Double, Double)]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for current in intervals.sorted(by: { $0.0 < $1.0 }) {
            if let last = result.last, current.0 <= last.1 {
                result[result.count - 1] = (last.0, max(last.1, current.1))
            } else {
                result.append(current)
            }
        }
        return result
    }

    static func unionLength(_ intervals: [(Double, Double)]) -> Double {
        merge(intervals).reduce(0) { $0 + ($1.1 - $1.0) }
    }
}
