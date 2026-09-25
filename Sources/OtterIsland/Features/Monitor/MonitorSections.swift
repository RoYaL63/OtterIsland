import AppKit
import SwiftUI

/// Couleurs partagées par les onglets de la fenêtre Moniteur.
@MainActor
enum MonitorStyle {
    static func tint(_ severity: HealthAdvisor.Severity) -> Color {
        switch severity {
        case .info: return .green
        case .advice: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    static func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Diagnostic

/// La réponse à « que dois-je faire ? » : le verdict, puis chaque constat avec
/// sa cause et, quand il y en a une, l'action en un clic.
struct MonitorDiagnosisView: View {
    let findings: [HealthAdvisor.Finding]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                verdict
                if findings.isEmpty {
                    Text("Aucun point particulier au moment du relevé. Le diagnostic s'affine avec l'onglet Historique, qui retient ce qui ralentit le Mac jour après jour.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(findings) { finding in
                    card(finding)
                }
            }
            .padding(16)
        }
    }

    private var verdict: some View {
        let verdict = HealthAdvisor.verdict(for: findings)
        return HStack(spacing: 12) {
            Image(systemName: verdict.severity >= .warning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(MonitorStyle.tint(verdict.severity))
            VStack(alignment: .leading, spacing: 2) {
                Text(verdict.title).font(.title2.weight(.semibold))
                Text(verdict.subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MonitorStyle.tint(verdict.severity).opacity(0.10))
        )
    }

    private func card(_ finding: HealthAdvisor.Finding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MonitorStyle.tint(finding.severity))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(finding.title).font(.body.weight(.semibold))
                    Text(finding.category.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                Text(finding.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = HealthAdvisor.label(for: finding.action) {
                    Button(label) { HealthAdvisor.perform(finding.action) }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Mémoire

/// La RAM ventilée comme dans le Moniteur d'activité, avec ce que chaque part
/// VEUT DIRE : du cache n'est pas de la mémoire perdue, du swap si.
struct MonitorMemoryView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var memory: MemoryMonitor

    private struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
        let explanation: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let b = memory.breakdown {
                    summary(b)
                    bar(b)
                    legend(b)
                    swap(b)
                } else {
                    Text("Relevé en cours…").foregroundStyle(.secondary)
                }
                topApps
            }
            .padding(16)
        }
    }

    private func segments(_ b: MemoryMonitor.Breakdown) -> [Segment] {
        [
            Segment(id: "Applications", value: b.app, color: .blue,
                    explanation: "Mémoire des apps ouvertes. C'est la part sur laquelle tu peux agir en fermant des apps ou des onglets."),
            Segment(id: "Câblée", value: b.wired, color: .orange,
                    explanation: "Réservée au système (noyau, pilotes, carte graphique). Ne peut être ni compressée ni déplacée."),
            Segment(id: "Compressée", value: b.compressed, color: .purple,
                    explanation: "Mémoire que macOS a compressée faute de place. Beaucoup de compression = la RAM commence à manquer."),
            Segment(id: "Cache", value: b.cached, color: .teal,
                    explanation: "Fichiers gardés en RAM pour aller plus vite. Libérés instantanément si besoin : ce n'est pas de la mémoire perdue."),
            Segment(id: "Libre", value: b.free, color: .gray.opacity(0.35),
                    explanation: "Réellement inoccupée. macOS préfère la remplir de cache plutôt que la laisser vide : peu de mémoire libre est normal."),
        ]
    }

    private func summary(_ b: MemoryMonitor.Breakdown) -> some View {
        let text: String
        switch memory.pressure {
        case .normal:
            text = memory.swapOutsPerSecond > 5
                ? "Pression normale, mais macOS écrit un peu sur le SSD : tu approches de la limite."
                : "Pression normale : la RAM suffit pour ce qui est ouvert."
        case .warning:
            text = "Pression élevée : macOS compresse et échange sur le SSD, les apps peuvent ralentir."
        case .critical:
            text = "Pression critique : la RAM est saturée, c'est la cause probable des ralentissements."
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(HealthAdvisor.format(bytes: b.used)) utilisés sur \(HealthAdvisor.format(bytes: b.total))")
                .font(.title3.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(memory.pressure == .normal ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bar(_ b: MemoryMonitor.Breakdown) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments(b)) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geo.size.width * segment.value / max(1, b.total) - 1))
                }
            }
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func legend(_ b: MemoryMonitor.Breakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments(b)) { segment in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(segment.color).frame(width: 12, height: 12)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(segment.id).font(.callout.weight(.semibold))
                            Spacer()
                            Text(HealthAdvisor.format(bytes: segment.value))
                                .font(.callout.monospacedDigit())
                        }
                        Text(segment.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func swap(_ b: MemoryMonitor.Breakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonitorStyle.sectionTitle("Swap (mémoire sur le SSD)")
            HStack {
                Text(b.swapUsed > 0
                     ? "\(HealthAdvisor.format(bytes: b.swapUsed)) utilisés"
                     : "Aucun swap")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(memory.swapOutsPerSecond >= 1
                     ? "\(Int(memory.swapOutsPerSecond)) pages/s écrites"
                     : "Pas d'écriture en cours")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(memory.swapOutsPerSecond > 20 ? .orange : .secondary)
            }
            Text("Le swap, c'est la RAM qui déborde sur le disque, cent fois plus lent. Un swap qui GRANDIT pendant que tu travailles explique les saccades ; un swap ancien et stable se vide au redémarrage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var topApps: some View {
        let apps = Array(monitor.apps.sorted { $0.memoryMB > $1.memoryMB }.prefix(8))
        let maxMB = apps.first?.memoryMB ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            MonitorStyle.sectionTitle("Qui occupe la RAM")
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    Text(app.name).font(.callout).lineLimit(1).frame(width: 170, alignment: .leading)
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: max(3, geo.size.width * app.memoryMB / max(1, maxMB)))
                    }
                    .frame(height: 6)
                    Text(app.memoryText)
                        .font(.caption.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Chaleur

/// Pourquoi ça chauffe : températures, ventilateurs, charge dans la durée, et
/// qui en est responsable.
struct MonitorHeatView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sensors
                load
                contributors
            }
            .padding(16)
        }
    }

    private var sensors: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorStyle.sectionTitle("Capteurs")
            HStack(alignment: .top, spacing: 24) {
                gauge("État thermique", monitor.thermalState.label, detail: monitor.thermalState.explanation)
                if let s = monitor.sensors, s.hasTemperatures {
                    gauge("Puce", "\(Int(s.cpuMax ?? 0)) °C",
                          detail: "Moyenne \(Int(s.cpuAverage ?? 0)) °C. Jusqu'à 95 °C sous charge, c'est normal pour une puce Apple.")
                    if let gpu = s.gpuAverage {
                        gauge("Graphique", "\(Int(gpu)) °C", detail: "Vidéo, jeux, écrans externes, apps 3D.")
                    }
                } else {
                    gauge("Températures", "Indisponibles",
                          detail: "Les sondes de cette puce ne répondent pas aux clés connues. L'état thermique de macOS reste fiable.")
                }
            }
            fans
        }
    }

    @ViewBuilder
    private var fans: some View {
        if let s = monitor.sensors {
            if s.fans.isEmpty {
                Text(s.fanCountKnown
                     ? "Ce Mac n'a pas de ventilateur : il se refroidit passivement, et ralentit plutôt que de souffler quand il chauffe."
                     : "Vitesse des ventilateurs indisponible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(s.fans, id: \.index) { fan in
                    HStack(spacing: 8) {
                        Image(systemName: "fanblades").foregroundStyle(fan.level >= 0.6 ? .orange : .secondary)
                        Text(s.fans.count > 1 ? "Ventilateur \(fan.index + 1)" : "Ventilateur")
                            .font(.callout)
                            .frame(width: 110, alignment: .leading)
                        ProgressView(value: fan.level)
                            .tint(fan.level >= 0.6 ? .orange : .accentColor)
                        Text("\(Int(fan.rpm)) tr/min")
                            .font(.callout.monospacedDigit())
                            .frame(width: 90, alignment: .trailing)
                    }
                    .help("Min \(Int(fan.minRPM)) — max \(Int(fan.maxRPM)) tr/min")
                }
            }
        }
    }

    private func gauge(_ label: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 190, alignment: .leading)
    }

    private var load: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonitorStyle.sectionTitle("Charge dans la durée")
            sparkline
                .frame(height: 50)
            HStack(spacing: 18) {
                loadValue("1 min", monitor.loadRatios[0])
                loadValue("5 min", monitor.loadRatios[1])
                loadValue("15 min", monitor.loadRatios[2])
                Spacer()
            }
            Text(trendText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trendText: String {
        let r = monitor.loadRatios
        if r[0] > 1 && r[2] > 1 { return "Saturé depuis plus de 15 minutes : c'est ce qui fait monter la température." }
        if r[0] > r[2] * 1.5 && r[0] > 0.5 { return "La charge vient de monter : quelque chose a démarré il y a peu." }
        if r[2] > r[0] * 1.5 && r[2] > 0.5 { return "La charge redescend : la chaleur devrait suivre." }
        return "1,00 = tous les cœurs occupés. La courbe montre les 5 dernières minutes (fenêtre ouverte)."
    }

    private func loadValue(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value).replacingOccurrences(of: ".", with: ","))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(value > 1 ? .orange : .primary)
        }
    }

    private var sparkline: some View {
        GeometryReader { geo in
            let points = monitor.cpuHistory
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04))
                if points.count > 1 {
                    Path { path in
                        for (i, value) in points.enumerated() {
                            let x = geo.size.width * Double(i) / Double(points.count - 1)
                            let y = geo.size.height * (1 - value)
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
        }
    }

    private var contributors: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonitorStyle.sectionTitle("Qui fait chauffer")
            ForEach(monitor.apps.prefix(6).filter { $0.cpu >= 3 }) { app in
                let known = app.processes.first.flatMap { KnownProcesses.info(for: $0.name) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(app.name).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(Int(monitor.share(of: app) * 100)) % de la charge")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(Int(app.cpu)) %")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(app.cpu > 80 ? .orange : .primary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    ProgressView(value: monitor.share(of: app))
                        .tint(app.cpu > 80 ? .orange : .accentColor)
                    if let known {
                        Text(known.explanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if battery.isCharging {
                Label("Recharge en cours : elle ajoute un peu de chaleur.", systemImage: "battery.100.bolt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if monitor.apps.prefix(6).allSatisfy({ $0.cpu < 3 }) {
                Text("Rien ne sollicite le processeur en ce moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Historique

/// Ce qui ralentit le Mac DE FAÇON RÉCURRENTE, sur les deux dernières semaines.
struct MonitorHistoryView: View {
    @ObservedObject var history: UsageHistory
    @EnvironmentObject var settings: OtterSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                if settings.monitorHistoryEnabled {
                    apps
                    pages
                }
            }
            .padding(16)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Suivre ce qui ralentit le Mac au fil des jours", isOn: $settings.monitorHistoryEnabled)
            Toggle("Noter les pages web ouvertes quand le navigateur s'emballe", isOn: $settings.monitorRecordPageTitles)
                .disabled(!settings.monitorHistoryEnabled)
            Text(introText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if settings.monitorRecordPageTitles && !WindowInspector.hasPermission {
                HStack(spacing: 6) {
                    Text("Les titres des pages demandent l'autorisation Accessibilité.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("Autoriser") { Paster.ensureAccessibility() }.controlSize(.mini)
                }
            }
        }
    }

    private var introText: String {
        var text = "Un relevé par minute, gardé 14 jours, uniquement sur ce Mac."
        if let first = history.firstSample {
            text += " Données depuis le \(Self.date.string(from: first))."
        }
        return text
    }

    private var apps: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                MonitorStyle.sectionTitle("Applications les plus pénalisantes")
                Spacer()
                Button("Effacer l'historique") { history.clear() }
                    .controlSize(.small)
            }
            if history.appSummaries.isEmpty {
                Text("Pas encore assez de relevés — reviens dans quelques heures d'utilisation.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                row(header: true, name: "Application", a: "CPU moy.", b: "RAM moy.", c: "Lourde", d: "Jours")
                ForEach(history.appSummaries.prefix(12)) { s in
                    let flagged = history.offenders.contains(s)
                    row(
                        header: false,
                        name: s.name,
                        a: "\(Int(s.averageCPU)) %",
                        b: HealthAdvisor.format(megabytes: s.averageMemoryMB),
                        c: "\(Int(s.heavyRatio * 100)) %",
                        d: "\(s.daysSeen)",
                        flagged: flagged
                    )
                    .help("Pic : \(Int(s.peakCPU)) % de CPU, \(HealthAdvisor.format(megabytes: s.peakMemoryMB)) de RAM — \(s.samples) relevés")
                }
                Text("« Lourde » = part du temps où l'app occupait plus d'un demi-cœur. En orange : celles qui pèsent régulièrement.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var pages: some View {
        if settings.monitorRecordPageTitles {
            VStack(alignment: .leading, spacing: 6) {
                MonitorStyle.sectionTitle("Pages présentes lors des emballements")
                if history.pageSummaries.isEmpty {
                    Text("Aucune page suspecte pour l'instant.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(history.pageSummaries.prefix(10)) { page in
                        HStack(spacing: 8) {
                            Image(systemName: "globe").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(page.name).font(.callout).lineLimit(1)
                                Text("\(page.bundleID ?? "") · \(page.samples) fois · \(Int(page.averageCPU)) % CPU moyen")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Text("Le titre est celui de l'onglet actif pendant que le navigateur dépassait 40 % de CPU. Une page qui revient souvent est un suspect sérieux ; pour une certitude, ouvre le gestionnaire de tâches du navigateur.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func row(header: Bool, name: String, a: String, b: String, c: String, d: String, flagged: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(a).frame(width: 70, alignment: .trailing)
            Text(b).frame(width: 80, alignment: .trailing)
            Text(c).frame(width: 60, alignment: .trailing)
            Text(d).frame(width: 44, alignment: .trailing)
        }
        .font(header ? .caption2.weight(.semibold) : .callout.monospacedDigit())
        .foregroundStyle(header ? Color.secondary : (flagged ? Color.orange : Color.primary))
    }

    private static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM 'à' HH:mm"
        return f
    }()
}
