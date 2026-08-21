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
        showBattery: Bool
    ) -> String {
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

        out += "## État actuel\n\n"
        out += "| Indicateur | Valeur | Lecture |\n|---|---|---|\n"
        out += "| État thermique | **\(monitor.thermalState.label)** | \(monitor.thermalState.explanation) |\n"
        out += "| Charge CPU | \(percent(monitor.cpuUsage)) | Somme des processus, ramenée aux \(monitor.coreCount) cœurs |\n"
        out += "| Charge moyenne (1 min) | \(decimal(monitor.loadRatio)) × cœurs | 1,00 = machine pleine |\n"
        out += "| Mémoire utilisée | \(percent(memory.usedFraction)) | Pression : \(pressureLabel(memory.pressure)) |\n"
        if showBattery {
            // « 100 % — sur batterie » est trompeur : macOS cesse d'annoncer la
            // charge dès que la batterie est pleine, alors que le Mac est
            // toujours branché.
            let state = battery.isCharging ? "en charge"
                : (battery.percentage >= 100 ? "pleine" : "sur batterie")
            out += "| Batterie | \(battery.percentage) % | \(state) |\n"
        }
        out += "\n"

        out += "## Ce qui consomme le CPU\n\n"
        out += table(monitor.topByCPU)
        out += "\n## Ce qui occupe la mémoire\n\n"
        out += table(monitor.topByMemory)

        out += "\n## Ce qui fait chauffer\n\n"
        out += diagnosis(monitor: monitor, memory: memory)

        out += "\n## Limites de ce rapport\n\n"
        out += """
        - La **température des cœurs** et la **vitesse des ventilateurs** ne sont pas lisibles \
        par une application ordinaire : elles vivent dans le SMC, dont l'accès demande `powermetrics` \
        en root ou un helper privilégié. Ce rapport s'appuie donc sur l'état thermique déclaré par \
        macOS, qui est la même information que celle utilisée par le système pour décider de brider.
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
