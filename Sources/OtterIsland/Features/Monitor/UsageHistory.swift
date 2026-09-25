import AppKit
import Foundation

/// Mémoire longue du moniteur : quelles applications — et quelles pages web —
/// pèsent sur le Mac JOUR APRÈS JOUR, et pas seulement à l'instant où l'on
/// ouvre l'onglet.
///
/// Un relevé instantané répond à « qu'est-ce qui rame maintenant ? ». La vraie
/// question est souvent « qu'est-ce qui me ralentit tout le temps ? » : l'app
/// qu'on garde ouverte toute la journée à 40 % de CPU, la web-app qui fait
/// souffler les ventilateurs à chaque fois qu'on l'ouvre. Il faut pour ça des
/// relevés espacés, accumulés sur plusieurs jours.
///
/// Coût : un `ps` par minute (quelques millisecondes), un fichier JSON de
/// quelques dizaines de Ko. Tout reste sur ce Mac.
@MainActor
final class UsageHistory: ObservableObject {

    /// Cumul d'une journée pour une application.
    struct DayStats: Codable, Equatable {
        var samples = 0
        var cpuSum = 0.0
        var memorySum = 0.0
        var peakCPU = 0.0
        var peakMemory = 0.0
        /// Relevés où l'app occupait plus d'un cœur à moitié (≥ 50 %).
        var heavySamples = 0
    }

    struct AppRecord: Codable, Equatable {
        var name: String
        var bundleID: String?
        var days: [String: DayStats] = [:]
    }

    /// Une page (titre de fenêtre de navigateur) vue pendant que son navigateur
    /// consommait fort.
    struct PageRecord: Codable, Equatable {
        var title: String
        var browser: String
        /// Jour → (nombre de relevés « lourds », somme du CPU du navigateur).
        var days: [String: DayStats] = [:]
    }

    private struct Store: Codable {
        var apps: [String: AppRecord] = [:]
        var pages: [String: PageRecord] = [:]
        var firstSample: Date?
    }

    /// Synthèse lisible d'un enregistrement sur la fenêtre d'analyse.
    struct Summary: Identifiable, Equatable {
        var id: String { key }
        let key: String
        let name: String
        let bundleID: String?
        /// Nombre de jours différents où elle a été vue.
        let daysSeen: Int
        let samples: Int
        /// CPU moyen pendant qu'elle tournait (100 % = un cœur).
        let averageCPU: Double
        let averageMemoryMB: Double
        let peakCPU: Double
        let peakMemoryMB: Double
        /// Part des relevés où elle était lourde, 0…1.
        let heavyRatio: Double

        /// Note de « nuisance » : combine intensité et régularité. Une app à
        /// 30 % en permanence gêne plus qu'une app à 200 % une fois.
        var impact: Double {
            averageCPU * (0.5 + heavyRatio) + averageMemoryMB / 100
        }
    }

    @Published private(set) var appSummaries: [Summary] = []
    @Published private(set) var pageSummaries: [Summary] = []
    @Published private(set) var firstSample: Date?
    @Published private(set) var isRunning = false

    private var store = Store()
    private var timer: Timer?
    private let fileName = "usage-history.json"
    /// Fenêtre d'analyse : au-delà, les jours sont supprimés.
    private let retentionDays = 14
    private let interval: TimeInterval = 60
    private var samplesSinceSave = 0
    /// Lecture des titres de fenêtres de navigateur, réglable.
    var recordPageTitles = true

    init() {
        store = Persistence.load(Store.self, from: fileName) ?? Store()
        prune()
        summarize()
    }

    func start() {
        guard timer == nil else { return }
        isRunning = true
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        // Tolérance large : le relevé n'a pas besoin d'être à la seconde, et
        // elle laisse macOS regrouper le réveil avec d'autres.
        t.tolerance = 15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        save()
    }

    func clear() {
        store = Store()
        save()
        summarize()
    }

    // MARK: Relevé

    private func sample() {
        let processes = SystemMonitor.sampleProcesses()
        let apps = SystemMonitor.group(processes)
        let day = Self.dayKey(Date())
        if store.firstSample == nil { store.firstSample = Date() }

        // Seules les apps qui PÈSENT entrent : noter les 300 démons à 0,1 %
        // gonflerait le fichier sans rien apprendre.
        for app in apps where app.cpu >= 2 || app.memoryMB >= 300 {
            let key = app.bundleID ?? app.name
            var record = store.apps[key] ?? AppRecord(name: app.name, bundleID: app.bundleID)
            record.name = app.name
            var stats = record.days[day] ?? DayStats()
            stats.samples += 1
            stats.cpuSum += app.cpu
            stats.memorySum += app.memoryMB
            stats.peakCPU = max(stats.peakCPU, app.cpu)
            stats.peakMemory = max(stats.peakMemory, app.memoryMB)
            if app.cpu >= 50 { stats.heavySamples += 1 }
            record.days[day] = stats
            store.apps[key] = record

            if recordPageTitles, app.cpu >= 40,
               let bundleID = app.bundleID, KnownProcesses.browserBundleIDs.contains(bundleID) {
                recordPages(of: app, day: day)
            }
        }

        samplesSinceSave += 1
        // Écriture toutes les 10 minutes : assez pour ne presque rien perdre
        // en cas de plantage, assez rare pour ne pas user le SSD.
        if samplesSinceSave >= 10 {
            prune()
            save()
        }
        summarize()
    }

    /// Le titre de fenêtre d'un navigateur est celui de l'onglet ACTIF. On ne
    /// peut pas savoir quel onglet précis consomme ; en revanche, une page qui
    /// revient systématiquement quand le navigateur s'emballe est un suspect
    /// sérieux.
    private func recordPages(of app: AppUsage, day: String) {
        let titles = WindowInspector.windowTitles(pid: app.id, limit: 3)
        for raw in titles {
            let title = Self.cleanTitle(raw, browser: app.name)
            guard !title.isEmpty else { continue }
            let key = "\(app.bundleID ?? app.name)|\(title)"
            var record = store.pages[key] ?? PageRecord(title: title, browser: app.name)
            var stats = record.days[day] ?? DayStats()
            stats.samples += 1
            stats.heavySamples += 1
            stats.cpuSum += app.cpu
            stats.memorySum += app.memoryMB
            stats.peakCPU = max(stats.peakCPU, app.cpu)
            stats.peakMemory = max(stats.peakMemory, app.memoryMB)
            record.days[day] = stats
            store.pages[key] = record
        }
    }

    /// « Airtable - Base CRM - Google Chrome - Augustin » → « Airtable - Base CRM ».
    static func cleanTitle(_ raw: String, browser: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [" - ", " — ", " – "] {
            if let range = title.range(of: separator + browser) {
                title = String(title[..<range.lowerBound])
            }
        }
        return String(title.prefix(90))
    }

    // MARK: Synthèse

    private func summarize() {
        firstSample = store.firstSample
        appSummaries = store.apps
            .map { Self.summary(key: $0.key, name: $0.value.name, bundleID: $0.value.bundleID, days: $0.value.days) }
            .filter { $0.samples >= 3 }
            .sorted { $0.impact > $1.impact }
        pageSummaries = store.pages
            .map { Self.summary(key: $0.key, name: $0.value.title, bundleID: $0.value.browser, days: $0.value.days) }
            .filter { $0.samples >= 2 }
            .sorted { $0.samples == $1.samples ? $0.averageCPU > $1.averageCPU : $0.samples > $1.samples }
    }

    private static func summary(key: String, name: String, bundleID: String?, days: [String: DayStats]) -> Summary {
        let all = days.values
        let samples = all.reduce(0) { $0 + $1.samples }
        let n = Double(max(1, samples))
        return Summary(
            key: key,
            name: name,
            bundleID: bundleID,
            daysSeen: days.count,
            samples: samples,
            averageCPU: all.reduce(0) { $0 + $1.cpuSum } / n,
            averageMemoryMB: all.reduce(0) { $0 + $1.memorySum } / n,
            peakCPU: all.map(\.peakCPU).max() ?? 0,
            peakMemoryMB: all.map(\.peakMemory).max() ?? 0,
            heavyRatio: Double(all.reduce(0) { $0 + $1.heavySamples }) / n
        )
    }

    /// Les applications qui ralentissent le Mac de façon RÉCURRENTE.
    var offenders: [Summary] {
        appSummaries.filter { summary in
            summary.samples >= 10 && (
                summary.averageCPU >= 25 || summary.heavyRatio >= 0.25 || summary.averageMemoryMB >= 2048
            )
        }
    }

    // MARK: Stockage

    private func prune() {
        guard let limit = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let cutoff = Self.dayKey(limit)
        for (key, var record) in store.apps {
            record.days = record.days.filter { $0.key >= cutoff }
            store.apps[key] = record.days.isEmpty ? nil : record
        }
        for (key, var record) in store.pages {
            record.days = record.days.filter { $0.key >= cutoff }
            store.pages[key] = record.days.isEmpty ? nil : record
        }
        if let first = store.firstSample, first < limit { store.firstSample = limit }
    }

    /// Appelé aussi à la fermeture de l'app : sans ça, jusqu'à dix minutes de
    /// relevés étaient perdues à chaque fois qu'on quittait.
    func save() {
        samplesSinceSave = 0
        Persistence.save(store, to: fileName)
    }

    /// « 2026-09-25 » : se trie comme une date, sans DateFormatter à la lecture.
    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
