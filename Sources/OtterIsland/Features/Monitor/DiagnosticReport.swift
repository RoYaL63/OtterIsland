import AppKit
import Foundation

/// Rapport de diagnostic en Markdown, prêt à être relu ou envoyé à quelqu'un.
///
/// Un rapport qui ne dit pas ce qu'il ne sait pas est un rapport trompeur :
/// la section « Limites » n'est pas de la modestie de façade, c'est ce qui
/// empêche de conclure « le Mac ne chauffe pas » alors qu'on n'a simplement
/// pas accès aux sondes.
@MainActor
enum DiagnosticReport {

    static func build(
        monitor: SystemMonitor,
        memory: MemoryMonitor,
        battery: BatteryMonitor,
        showBattery: Bool,
        history: UsageHistory? = nil
    ) -> String {
        let findings = HealthAdvisor.findings(monitor: monitor, memory: memory, battery: battery, history: history)
        let verdict = HealthAdvisor.verdict(for: findings)
        var out = ""
        out += "# Diagnostic système — OtterIsland\n\n"
        out += "_Généré le \(stamp.string(from: Date()))_\n\n"

        out += "## Machine\n\n"
        out += "| | |\n|---|---|\n"
        out += "| Modèle | \(SystemMonitor.hardwareModel) |\n"
        out += "| Puce | \(SystemMonitor.chip) |\n"
        out += "| Cœurs | \(monitor.coreCount) |\n"
        out += "| macOS | \(ProcessInfo.processInfo.operatingSystemVersionString) |\n"
        out += "| Allumé depuis | \(uptime()) |\n\n"

        out += "## Verdict\n\n"
        out += "**\(verdict.title)** — \(verdict.subtitle)\n\n"
        for finding in findings {
            let action = HealthAdvisor.label(for: finding.action).map { " → _\($0)_" } ?? ""
            out += "- **[\(finding.category.rawValue)] \(finding.title)** — \(finding.detail)\(action)\n"
        }
        out += "\n"

        out += "## État actuel\n\n"
        out += "| Indicateur | Valeur | Lecture |\n|---|---|---|\n"
        out += "| État thermique | **\(monitor.thermalState.label)** | \(monitor.thermalState.explanation) |\n"
        out += "| Charge CPU | \(percent(monitor.cpuUsage)) | Somme des processus, ramenée aux \(monitor.coreCount) cœurs |\n"
        out += "| Charge moyenne (1 min) | \(decimal(monitor.loadRatio)) × cœurs | 1,00 = machine pleine |\n"
        out += "| Mémoire utilisée | \(percent(memory.usedFraction)) | Pression : \(pressureLabel(memory.pressure)) |\n"
        if let sensors = monitor.sensors {
            if let cpu = sensors.cpuMax {
                out += "| Température puce | \(Int(cpu)) °C | moyenne \(Int(sensors.cpuAverage ?? cpu)) °C |\n"
            }
            for fan in sensors.fans {
                out += "| Ventilateur \(fan.index + 1) | \(Int(fan.rpm)) tr/min | min \(Int(fan.minRPM)), max \(Int(fan.maxRPM)) |\n"
            }
        }
        if monitor.diskTotal > 0 {
            out += "| Disque libre | \(HealthAdvisor.format(bytes: monitor.diskFree)) | sur \(HealthAdvisor.format(bytes: monitor.diskTotal)) |\n"
        }
        if showBattery {
            // « 100 % — sur batterie » est trompeur : macOS cesse d'annoncer la
            // charge dès que la batterie est pleine, alors que le Mac est
            // toujours branché.
            let state = battery.isCharging ? "en charge"
                : (battery.percentage >= 100 ? "pleine" : "sur batterie")
            out += "| Batterie | \(battery.percentage) % | \(state) |\n"
        }
        out += "\n"

        if let b = memory.breakdown {
            out += "## Mémoire en détail\n\n"
            out += "| Part | Taille |\n|---|---:|\n"
            out += "| Applications | \(HealthAdvisor.format(bytes: b.app)) |\n"
            out += "| Câblée (système) | \(HealthAdvisor.format(bytes: b.wired)) |\n"
            out += "| Compressée | \(HealthAdvisor.format(bytes: b.compressed)) |\n"
            out += "| Cache (libérable) | \(HealthAdvisor.format(bytes: b.cached)) |\n"
            out += "| Libre | \(HealthAdvisor.format(bytes: b.free)) |\n"
            out += "| Swap sur le SSD | \(HealthAdvisor.format(bytes: b.swapUsed)) |\n\n"
        }

        out += "## Consommation par application\n\n"
        out += appTable(monitor.apps)
        out += "\n## Ce qui consomme le CPU (processus bruts)\n\n"
        out += table(monitor.topByCPU)
        out += "\n## Ce qui occupe la mémoire\n\n"
        out += table(monitor.topByMemory)

        out += "\n## Ce qui fait chauffer\n\n"
        out += diagnosis(monitor: monitor, memory: memory)

        if let history, !history.appSummaries.isEmpty {
            out += "\n## Sur les 14 derniers jours\n\n"
            out += "| Application | CPU moyen | RAM moyenne | Lourde | Jours |\n|---|---:|---:|---:|---:|\n"
            for s in history.appSummaries.prefix(10) {
                out += "| \(s.name) | \(Int(s.averageCPU)) % | \(HealthAdvisor.format(megabytes: s.averageMemoryMB)) | \(Int(s.heavyRatio * 100)) % | \(s.daysSeen) |\n"
            }
            if !history.pageSummaries.isEmpty {
                out += "\n**Pages ouvertes lors des emballements du navigateur :**\n\n"
                for page in history.pageSummaries.prefix(8) {
                    out += "- \(page.name) (\(page.bundleID ?? "")) — \(page.samples) fois, \(Int(page.averageCPU)) % CPU moyen\n"
                }
            }
        }

        out += "\n## Limites de ce rapport\n\n"
        out += """
        - La **température** et les **ventilateurs** sont lus dans le SMC. Apple ne documente pas \
        les clés de température, qui changent d'une puce à l'autre : si elles manquent, le rapport \
        s'appuie sur l'état thermique déclaré par macOS, celui que le système utilise pour brider.
        - Le CPU d'un navigateur est celui de TOUTE l'application : les titres de pages indiquent \
        l'onglet actif pendant un emballement, pas une mesure onglet par onglet.
        - Les pourcentages CPU sont ceux de `ps`, c'est-à-dire une moyenne depuis le dernier relevé, \
        pas une valeur instantanée. Un pic très court peut ne pas y apparaître.
        - Le pourcentage CPU est exprimé **par cœur** : 100 % signifie un cœur saturé, pas la machine.

        """
        return out
    }

    // MARK: Analyse

    /// La partie qui a de la valeur : relier les chiffres à une cause probable.
    /// Sans elle, le rapport n'est qu'un `ps` mis en forme.
    private static func diagnosis(monitor: SystemMonitor, memory: MemoryMonitor) -> String {
        var lines: [String] = []

        if let worst = monitor.topByCPU.first, worst.cpu > 50 {
            lines.append("- **\(worst.name)** occupe \(Int(worst.cpu)) % d'un cœur à lui seul — c'est le premier suspect.")
        }
        let heavy = monitor.topByCPU.filter { $0.cpu > 20 }
        if heavy.count >= 3 {
            lines.append("- \(heavy.count) processus dépassent 20 % de CPU en même temps : la chauffe vient d'un cumul, pas d'un coupable unique.")
        }
        if monitor.loadRatio > 1 {
            lines.append("- La charge moyenne dépasse le nombre de cœurs (\(decimal(monitor.loadRatio)) ×) : des processus attendent leur tour, la machine est saturée.")
        }
        if memory.usedFraction > 0.9 {
            lines.append("- La mémoire est à \(percent(memory.usedFraction)) : la compression et le swap consomment du CPU, ce qui fait chauffer sans qu'aucune app n'ait l'air fautive.")
        }
        switch monitor.thermalState {
        case .serious, .critical:
            lines.append("- macOS **bride déjà** les performances (\(monitor.thermalState.label.lowercased())) : tout paraîtra lent tant que la température n'est pas redescendue.")
        case .nominal where lines.isEmpty:
            lines.append("- Rien d'anormal au moment du relevé : état thermique normal, aucun processus dominant.")
        default:
            break
        }
        if lines.isEmpty {
            lines.append("- Aucune cause franche au moment du relevé.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Mise en forme

    /// Le tableau qui compte : cinq « Google Chrome Helper » à 17 % ne disent
    /// rien, « Google Chrome — 84 %, 12 processus » se comprend.
    private static func appTable(_ apps: [AppUsage]) -> String {
        guard !apps.isEmpty else { return "_Aucun relevé._\n" }
        var out = "| Application | CPU | Mémoire | Processus |\n|---|---:|---:|---:|\n"
        for app in apps.prefix(10) where app.cpu > 0.5 || app.memoryMB > 100 {
            out += "| \(app.name) | \(decimal(app.cpu, digits: 1)) % | \(String(format: "%.0f", app.memoryMB)) Mo | \(app.processCount) |\n"
        }
        return out
    }

    private static func table(_ rows: [SystemMonitor.ProcessUsage]) -> String {
        guard !rows.isEmpty else { return "_Aucun relevé._\n" }
        var out = "| Processus | PID | CPU | Mémoire |\n|---|---:|---:|---:|\n"
        for row in rows {
            out += "| \(row.name) | \(row.id) | \(decimal(row.cpu, digits: 1)) % | \(String(format: "%.0f", row.memoryMB)) Mo |\n"
        }
        return out
    }

    /// Virgule décimale : le rapport est en français, un « 0.38 » au milieu de
    /// « 1,00 = machine pleine » se voit.
    private static func decimal(_ value: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) %"
    }

    private static func pressureLabel(_ pressure: MemoryMonitor.Pressure) -> String {
        switch pressure {
        case .normal: return "normale"
        case .warning: return "élevée"
        case .critical: return "critique"
        }
    }

    private static func uptime() -> String {
        let seconds = Int(ProcessInfo.processInfo.systemUptime)
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days) j \(hours) h" }
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM yyyy 'à' HH:mm"
        return f
    }()

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()

    // MARK: Enregistrement

    /// Propose l'enregistrement du rapport. Un panneau plutôt qu'un chemin
    /// imposé : un diagnostic se range où son auteur le décide, et le voir
    /// atterrir sans prévenir sur le Bureau serait une surprise de plus.
    @discardableResult
    static func save(_ markdown: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OtterIsland-diagnostic-\(fileStamp.string(from: Date())).md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.title = "Enregistrer le diagnostic"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try? markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
