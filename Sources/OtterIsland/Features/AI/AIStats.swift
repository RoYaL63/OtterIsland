import Foundation

// MARK: - Périodes et résultats

/// Fenêtre d'analyse de l'onglet Assistants IA.
enum AIPeriod: String, CaseIterable, Identifiable {
    case today, week, month

    var id: String { rawValue }
    var days: Int {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        }
    }
    var title: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .week: return "7 jours"
        case .month: return "30 jours"
        }
    }
    /// Pour la barre de l'île, où la place est comptée.
    var shortTitle: String {
        switch self {
        case .today: return "Auj."
        case .week: return "7 j"
        case .month: return "30 j"
        }
    }
}

/// Ce que l'assistant a fait sur un projet pendant la période.
struct AIProjectStat: Identifiable, Equatable {
    /// Racine du projet (dossier du dépôt git, ou dossier de travail).
    let id: String
    var name: String
    var tokens = TokenCount()
    /// Temps pendant lequel ça a travaillé : voir `AIStatsEngine.idleGap`.
    var activeSeconds: Double = 0
    /// Conversations (une session = un journal), sous-agents exclus.
    var sessions = 0
    var lastActivity: Date?
}

struct AIStatsSnapshot: Equatable {
    var period: AIPeriod
    var tokens = TokenCount()
    var activeSeconds: Double = 0
    var sessions = 0
    /// Du plus actif au moins actif.
    var projects: [AIProjectStat] = []
    /// Temps actif de chaque jour de la période, du plus ancien au plus récent.
    var dailyActiveSeconds: [Double] = []
    var lastActivity: Date?
    /// Projet de la conversation la plus récente.
    var currentProject: String?
    /// Toutes les sessions ont été lues (sinon l'analyse continue).
    var isComplete = true

    /// Actif = écrit dans les 5 dernières minutes.
    var isActive: Bool {
        guard let lastActivity else { return false }
        return Date().timeIntervalSince(lastActivity) < 5 * 60
    }
}

// MARK: - Lecture des lignes

/// Lecture d'une ligne de journal sans la décoder en entier : une ligne
/// d'outil pèse jusqu'à 1,3 Mo, et il y en a des dizaines de milliers. On
/// cherche seulement ce dont on a besoin (type, horodatage, dossier, tokens),
/// avec `memmem`, et on ne décode que le petit objet `usage`.
enum AILineReader {
    typealias Bytes = UnsafeBufferPointer<UInt8>

    /// Position de `needle` dans `hay` à partir de `from`.
    static func find(_ hay: Bytes, _ needle: StaticString, from: Int = 0) -> Int? {
        guard from >= 0, from < hay.count, let base = hay.baseAddress else { return nil }
        let start = base + from
        guard let hit = memmem(start, hay.count - from, needle.utf8Start, needle.utf8CodeUnitCount) else { return nil }
        return UnsafePointer<UInt8>(hit.assumingMemoryBound(to: UInt8.self)) - base
    }

    /// Horodatage ISO 8601 (« 2026-10-05T09:57:16.518Z ») qui suit la clé, en
    /// secondes depuis 1970 (UTC).
    static func timestamp(in line: Bytes) -> Double? {
        guard let key = find(line, "\"timestamp\":\"") else { return nil }
        return isoSeconds(line, at: key + 13)
    }

    static func isoSeconds(_ b: Bytes, at i: Int) -> Double? {
        guard i + 19 <= b.count else { return nil }
        func num(_ from: Int, _ count: Int) -> Int? {
            var v = 0
            for k in from..<from + count {
                let c = Int(b[k]) - 48
                guard (0...9).contains(c) else { return nil }
                v = v * 10 + c
            }
            return v
        }
        guard let y = num(i, 4), let mo = num(i + 5, 2), let d = num(i + 8, 2),
              let h = num(i + 11, 2), let mi = num(i + 14, 2), let s = num(i + 17, 2),
              b[i + 4] == 45, b[i + 10] == 84
        else { return nil }
        // Fraction de seconde éventuelle.
        var fraction = 0.0
        var k = i + 19
        if k < b.count, b[k] == 46 {
            var scale = 0.1
            k += 1
            while k < b.count, (48...57).contains(b[k]) {
                fraction += Double(Int(b[k]) - 48) * scale
                scale /= 10
                k += 1
            }
        }
        // Jours depuis 1970 (algorithme civil de Howard Hinnant).
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let doy = (153 * (mo + (mo > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468
        return Double(days * 86_400 + h * 3600 + mi * 60 + s) + fraction
    }

    /// Valeur d'une clé texte (`"cwd":"/Users/…"`), `\\` et `\"` décodés.
    static func string(in line: Bytes, key: StaticString) -> String? {
        guard let at = find(line, key) else { return nil }
        let start = at + key.utf8CodeUnitCount
        var end = start
        var escaped = false
        while end < line.count {
            let c = line[end]
            if escaped { escaped = false } else if c == 92 { escaped = true } else if c == 34 { break }
            end += 1
        }
        guard end < line.count else { return nil }
        let raw = String(decoding: UnsafeBufferPointer(rebasing: line[start..<end]), as: UTF8.self)
        guard raw.contains("\\") else { return raw }
        return (try? JSONSerialization.jsonObject(with: Data("\"\(raw)\"".utf8), options: .fragmentsAllowed)) as? String ?? raw
    }

    /// L'objet JSON qui commence à `open` (une accolade), jusqu'à son
    /// accolade fermante : les chaînes sont sautées, elles peuvent contenir des accolades.
    static func object(in line: Bytes, startingAt open: Int) -> [String: Any]? {
        guard open < line.count, line[open] == 123 else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = open
        while i < line.count {
            let c = line[i]
            if inString {
                if escaped { escaped = false } else if c == 92 { escaped = true } else if c == 34 { inString = false }
            } else if c == 34 {
                inString = true
            } else if c == 123 {
                depth += 1
            } else if c == 125 {
                depth -= 1
                if depth == 0 {
                    let data = Data(UnsafeBufferPointer(rebasing: line[open...i]))
                    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }
            }
            i += 1
        }
        return nil
    }

    /// L'objet qui suit `key` (ex. `"usage":`).
    static func object(in line: Bytes, after key: StaticString) -> [String: Any]? {
        guard let at = find(line, key) else { return nil }
        return object(in: line, startingAt: at + key.utf8CodeUnitCount)
    }
}

/// Mise en forme des durées.
enum AIFormat {
    /// 45 → « < 1 min », 2 520 → « 42 min », 12 000 → « 3 h 20 ».
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if seconds < 30 { return "0 min" }
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))"
    }
}
