import AppKit
import Foundation

/// Transforme les relevés en DIAGNOSTIC : qu'est-ce qui ne va pas, pourquoi, et
/// quoi faire — redémarrer, faire de la place, fermer une app, ou attendre.
///
/// Chaque règle part d'un seuil documenté plutôt que d'une impression. Quand
/// rien ne dépasse, le verdict le dit franchement : « tout va bien » est une
/// réponse utile, pas un échec du diagnostic.
@MainActor
enum HealthAdvisor {

    enum Severity: Int, Comparable {
        case info = 0, advice = 1, warning = 2, critical = 3

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    enum Category: String {
        case heat = "Chaleur"
        case memory = "Mémoire"
        case cpu = "Processeur"
        case storage = "Stockage"
        case system = "Système"
        case habits = "Habitudes"
    }

    enum Action: Equatable {
        case restart
        case openStorageSettings
        case quitApp(pid: pid_t, name: String)
        case openActivityMonitor
        case nothing
    }

    struct Finding: Identifiable, Equatable {
        let id: String
        let severity: Severity
        let category: Category
        let icon: String
        let title: String
        let detail: String
        var action: Action = .nothing
    }

    /// Réponse courte à « faut-il faire quelque chose ? ».
    struct Verdict: Equatable {
        let title: String
        let subtitle: String
        let severity: Severity
    }

    // MARK: Analyse

    static func findings(
        monitor: SystemMonitor,
        memory: MemoryMonitor,
        battery: BatteryMonitor,
        history: UsageHistory?
    ) -> [Finding] {
        var out: [Finding] = []
        out += heat(monitor: monitor, battery: battery)
        out += cpu(monitor: monitor)
        out += ram(monitor: monitor, memory: memory)
        out += storage(monitor: monitor)
        out += system(monitor: monitor, memory: memory)
        if let history { out += habits(history: history, monitor: monitor) }
        return out.sorted { $0.severity > $1.severity }
    }

    static func verdict(for findings: [Finding]) -> Verdict {
        let actionable = findings.filter { $0.severity >= .advice }
        if findings.contains(where: { $0.action == .restart && $0.severity >= .warning }) {
            return Verdict(title: "Redémarrage conseillé",
                           subtitle: "Un redémarrage videra la mémoire et le swap accumulés.",
                           severity: .warning)
        }
        if let storage = findings.first(where: { $0.action == .openStorageSettings && $0.severity >= .warning }) {
            return Verdict(title: "Fais de la place sur le disque", subtitle: storage.title, severity: storage.severity)
        }
        guard let worst = actionable.first else {
            return Verdict(title: "Tout va bien",
                           subtitle: "Aucune cause de ralentissement ni de chauffe détectée.",
                           severity: .info)
        }
        let others = actionable.count - 1
        return Verdict(
            title: worst.title,
            subtitle: others > 0 ? "Et \(others) autre\(others > 1 ? "s" : "") point\(others > 1 ? "s" : "") à regarder." : worst.category.rawValue,
            severity: worst.severity
        )
    }

    // MARK: Chaleur

    private static func heat(monitor: SystemMonitor, battery: BatteryMonitor) -> [Finding] {
        var out: [Finding] = []
        let thermal = monitor.thermalState
        let sensors = monitor.sensors
        let hottest = monitor.apps.first

        if thermal == .serious || thermal == .critical {
            var why = "macOS bride déjà le processeur pour faire baisser la température : tout paraît lent."
            if let hottest, hottest.cpu > 40 {
                why += " Principale source : \(hottest.name) (\(Int(monitor.share(of: hottest) * 100)) % de la charge)."
            }
            out.append(Finding(
                id: "heat.throttle", severity: thermal == .critical ? .critical : .warning, category: .heat,
                icon: "thermometer.high", title: "Le Mac surchauffe", detail: why,
                action: hottest.map { quitAction($0) } ?? .nothing
            ))
        }

        if let cpuTemp = sensors?.cpuMax, cpuTemp >= 90 {
            out.append(Finding(
                id: "heat.temp", severity: cpuTemp >= 100 ? .warning : .advice, category: .heat,
                icon: "flame", title: "Puce à \(Int(cpuTemp)) °C",
                detail: "Au-delà de 90 °C la puce ralentit pour se protéger. Une charge soutenue en est presque toujours la cause : \(Int(monitor.sustainedCPU * 100)) % de CPU en moyenne sur les dernières minutes."
            ))
        }

        if let fan = sensors?.fans.max(by: { $0.level < $1.level }), fan.level >= 0.6 {
            let reason: String
            if monitor.sustainedCPU > 0.4, let hottest {
                reason = "Ils évacuent la chaleur d'une charge soutenue, surtout due à \(hottest.name)."
            } else if monitor.sustainedCPU < 0.2 {
                reason = "La charge est pourtant faible : environnement chaud, Mac posé sur une surface molle, ou poussière dans les aérations."
            } else {
                reason = "Ils suivent la charge du processeur."
            }
            out.append(Finding(
                id: "heat.fans", severity: .advice, category: .heat,
                icon: "fanblades", title: "Ventilateurs à \(Int(fan.rpm)) tr/min", detail: reason
            ))
        }

        if battery.isCharging, thermal != .nominal {
            out.append(Finding(
                id: "heat.charging", severity: .info, category: .heat,
                icon: "battery.100.bolt",
                title: "La recharge ajoute de la chaleur",
                detail: "Charger la batterie chauffe le Mac en plus du travail en cours. C'est normal ; ça se calme une fois la batterie pleine."
            ))
        }

        if let kernel = monitor.topByCPU.first(where: { $0.name == "kernel_task" }), kernel.cpu > 50 {
            out.append(Finding(
                id: "heat.kernel", severity: .advice, category: .heat,
                icon: "exclamationmark.thermometer",
                title: "macOS freine le processeur (kernel_task \(Int(kernel.cpu)) %)",
                detail: KnownProcesses.info(for: "kernel_task")?.explanation ?? ""
            ))
        }
        return out
    }

    // MARK: Processeur

    private static func cpu(monitor: SystemMonitor) -> [Finding] {
        var out: [Finding] = []

        for app in monitor.apps.prefix(4) where app.cpu >= 60 {
            let known = app.processes.first.flatMap { KnownProcesses.info(for: $0.name) }
            if let known, known.kind == .transient {
                out.append(Finding(
                    id: "cpu.transient.\(app.id)", severity: .info, category: .cpu,
                    icon: "hourglass",
                    title: "\(known.label) travaille (\(Int(app.cpu)) %)",
                    detail: known.explanation + " Inutile de l'arrêter."
                ))
            } else {
                let cores = app.cpu / 100
                var detail = cores >= 1.5
                    ? "Occupe l'équivalent de \(String(format: "%.1f", cores).replacingOccurrences(of: ".", with: ",")) cœurs à lui seul."
                    : "Occupe \(Int(app.cpu)) % d'un cœur."
                detail += " \(Int(monitor.share(of: app) * 100)) % de toute la charge du Mac."
                if let known { detail += " " + known.explanation }
                if app.processCount > 15, KnownProcesses.browserBundleIDs.contains(app.bundleID ?? "") {
                    detail += " \(app.processCount) processus : beaucoup d'onglets ou d'extensions ouverts."
                }
                out.append(Finding(
                    id: "cpu.hog.\(app.id)", severity: app.cpu >= 150 ? .warning : .advice, category: .cpu,
                    icon: "cpu", title: "\(app.name) consomme beaucoup", detail: detail,
                    action: quitAction(app)
                ))
            }
        }

        if monitor.loadRatios[0] > 1.2 && monitor.loadRatios[2] > 1 {
            out.append(Finding(
                id: "cpu.saturated", severity: .warning, category: .cpu, icon: "gauge.with.dots.needle.100percent",
                title: "Processeur saturé depuis un moment",
                detail: "Plus de tâches en attente que de cœurs, depuis plus de 15 minutes. Tout ce que tu lances passe après elles."
            ))
        }
        return out
    }

    // MARK: Mémoire

    private static func ram(monitor: SystemMonitor, memory: MemoryMonitor) -> [Finding] {
        var out: [Finding] = []
        let gb = 1_073_741_824.0

        if memory.pressure != .normal || memory.swapOutsPerSecond > 20 {
            let top = monitor.apps.sorted { $0.memoryMB > $1.memoryMB }.first
            var detail = "La RAM ne suffit plus : macOS compresse la mémoire et écrit sur le SSD (swap), ce qui produit les saccades et les roues multicolores."
            if let top {
                detail += " \(top.name) occupe à lui seul \(top.memoryText)."
            }
            out.append(Finding(
                id: "ram.pressure", severity: memory.pressure == .critical ? .critical : .warning, category: .memory,
                icon: "memorychip", title: "Mémoire saturée", detail: detail,
                action: top.map { quitAction($0) } ?? .nothing
            ))
        }

        if let b = memory.breakdown {
            if b.swapUsed > max(2 * gb, b.total * 0.25) {
                out.append(Finding(
                    id: "ram.swap", severity: b.swapUsed > b.total * 0.5 ? .warning : .advice, category: .memory,
                    icon: "externaldrive.badge.timemachine",
                    title: "\(format(bytes: b.swapUsed)) de swap sur le SSD",
                    detail: "macOS a déplacé de la mémoire sur le disque. Même une fois les apps fermées, ce swap ne redescend que lentement ; un redémarrage le vide d'un coup.",
                    action: .restart
                ))
            }
            if b.cached > b.total * 0.3, memory.pressure == .normal {
                out.append(Finding(
                    id: "ram.cache", severity: .info, category: .memory, icon: "tray.full",
                    title: "\(format(bytes: b.cached)) de cache : c'est une bonne chose",
                    detail: "Fichiers gardés en RAM pour être relus instantanément. macOS les libère dès qu'une app en a besoin : une RAM « pleine » de cache n'est pas une RAM saturée."
                ))
            }
        }

        if let windowServer = monitor.topByMemory.first(where: { $0.name == "WindowServer" }),
           windowServer.memoryMB > 1536 {
            out.append(Finding(
                id: "ram.windowserver", severity: .advice, category: .memory, icon: "macwindow.on.rectangle",
                title: "L'affichage occupe \(format(megabytes: windowServer.memoryMB))",
                detail: "WindowServer grossit au fil des jours (fenêtres, écrans externes). Une fermeture de session ou un redémarrage le remet à zéro.",
                action: .restart
            ))
        }
        return out
    }

    // MARK: Stockage

    private static func storage(monitor: SystemMonitor) -> [Finding] {
        guard monitor.diskTotal > 0 else { return [] }
        let free = monitor.diskFree
        let ratio = free / monitor.diskTotal
        let gb = 1_073_741_824.0
        guard free < 20 * gb || ratio < 0.1 else { return [] }
        let critical = free < 10 * gb || ratio < 0.05
        return [Finding(
            id: "disk.low", severity: critical ? .critical : .warning, category: .storage,
            icon: "internaldrive",
            title: "Plus que \(format(bytes: free)) libres",
            detail: "Un SSD presque plein ralentit tout le Mac : macOS n'a plus la place d'agrandir son swap ni ses caches, et les mises à jour échouent. Vise au moins 20 Go libres — Réglages › Stockage liste les gros fichiers, la corbeille et les pièces jointes à supprimer.",
            action: .openStorageSettings
        )]
    }

    // MARK: Système

    private static func system(monitor: SystemMonitor, memory: MemoryMonitor) -> [Finding] {
        let uptime = ProcessInfo.processInfo.systemUptime
        let days = Int(uptime / 86_400)
        let swap = memory.breakdown?.swapUsed ?? 0
        let gb = 1_073_741_824.0

        if days >= 14 || (days >= 7 && (swap > 2 * gb || memory.pressure != .normal)) {
            return [Finding(
                id: "sys.uptime", severity: days >= 14 || swap > 4 * gb ? .warning : .advice, category: .system,
                icon: "arrow.clockwise.circle",
                title: "Allumé depuis \(days) jours",
                detail: "Au fil des jours, mémoire fragmentée, swap et caches s'accumulent, et certaines mises à jour de sécurité attendent un redémarrage pour s'appliquer. Un redémarrage par semaine suffit.",
                action: .restart
            )]
        }
        return []
    }

    // MARK: Habitudes

    private static func habits(history: UsageHistory, monitor: SystemMonitor) -> [Finding] {
        var out: [Finding] = []
        for offender in history.offenders.prefix(3) {
            var parts: [String] = []
            parts.append("En moyenne \(Int(offender.averageCPU)) % de CPU et \(format(megabytes: offender.averageMemoryMB)) de RAM quand elle est ouverte")
            if offender.heavyRatio >= 0.1 {
                parts.append("lourde \(Int(offender.heavyRatio * 100)) % du temps")
            }
            parts.append("vue \(offender.daysSeen) jour\(offender.daysSeen > 1 ? "s" : "") sur les deux dernières semaines")
            let running = monitor.apps.first { ($0.bundleID ?? $0.name) == offender.key }
            out.append(Finding(
                id: "habit.\(offender.key)", severity: .advice, category: .habits,
                icon: "clock.arrow.circlepath",
                title: "\(offender.name) ralentit régulièrement le Mac",
                detail: parts.joined(separator: ", ") + ". Ferme-la quand tu ne t'en sers pas, ou cherche une version plus légère (web vs app, moins d'extensions).",
                action: running.map { quitAction($0) } ?? .nothing
            ))
        }
        if let page = history.pageSummaries.first, page.samples >= 5 {
            out.append(Finding(
                id: "habit.page", severity: .advice, category: .habits, icon: "globe",
                title: "« \(page.name) » revient à chaque emballement",
                detail: "Cette page était ouverte \(page.samples) fois quand \(page.bundleID ?? "le navigateur") dépassait 40 % de CPU (\(Int(page.averageCPU)) % en moyenne). Les web-apps lourdes (tableurs, bases, outils de design) gagnent à être fermées, ou ouvertes dans un seul onglet."
            ))
        }
        return out
    }

    // MARK: Actions

    /// Une app avec interface se quitte proprement ; un démon se regarde dans
    /// le Moniteur d'activité plutôt que de se tuer à l'aveugle.
    private static func quitAction(_ app: AppUsage) -> Action {
        app.isGUI ? Action.quitApp(pid: app.id, name: app.name) : Action.openActivityMonitor
    }

    static func perform(_ action: Action) {
        switch action {
        case .restart:
            let alert = NSAlert()
            alert.messageText = "Redémarrer le Mac ?"
            alert.informativeText = "macOS proposera d'enregistrer les documents ouverts avant de redémarrer."
            alert.addButton(withTitle: "Annuler")
            alert.addButton(withTitle: "Redémarrer")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            // Passer par System Events, c'est demander à macOS le redémarrage
            // « normal » (celui du menu Pomme) : chaque app peut refuser ou
            // demander d'enregistrer.
            let script = NSAppleScript(source: "tell application \"System Events\" to restart")
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            if error != nil {
                // Autorisation Automatisation refusée : on n'insiste pas, on
                // indique le chemin manuel.
                let fallback = NSAlert()
                fallback.messageText = "Redémarrage impossible depuis OtterIsland"
                fallback.informativeText = "Autorise OtterIsland à piloter « System Events » (Réglages Système › Confidentialité › Automatisation), ou passe par le menu Pomme › Redémarrer."
                fallback.runModal()
            }
        case .openStorageSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                NSWorkspace.shared.open(url)
            }
        case .quitApp(let pid, _):
            _ = ProcessTerminator.quit(pid: pid)
        case .openActivityMonitor:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
        case .nothing:
            break
        }
    }

    static func label(for action: Action) -> String? {
        switch action {
        case .restart: return "Redémarrer…"
        case .openStorageSettings: return "Ouvrir Stockage"
        case .quitApp(_, let name): return "Quitter \(name)"
        case .openActivityMonitor: return "Moniteur d'activité"
        case .nothing: return nil
        }
    }

    // MARK: Format

    static func format(bytes: Double) -> String {
        let gb = bytes / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f Go", gb).replacingOccurrences(of: ".", with: ",") }
        return "\(Int(bytes / 1_048_576)) Mo"
    }

    static func format(megabytes: Double) -> String {
        format(bytes: megabytes * 1_048_576)
    }
}
