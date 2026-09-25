import SwiftUI

/// Onglet Moniteur : ce qui consomme, ce qui chauffe, et un rapport à emporter.
///
/// Le Moniteur d'activité d'Apple répond à « quel processus » ; il ne répond pas
/// à « pourquoi mon Mac chauffe ». C'est ce que cet onglet cherche à faire tenir
/// en un coup d'œil : l'état thermique déclaré par macOS À CÔTÉ des processus
/// qui le provoquent, dans la même carte.
struct MonitorPanel: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var memory: MemoryMonitor
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var history: UsageHistory
    @EnvironmentObject var settings: OtterSettings
    let showBattery: Bool
    /// Ouvre la fenêtre détaillée (processus, fenêtres, arrêt forcé).
    var onOpenWindow: (() -> Void)?

    /// Chemin du dernier rapport enregistré : le lien devient « Révéler », pour
    /// qu'on retrouve le fichier sans se demander où il est parti.
    @State private var savedReport: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                OtterTile {
                    stateColumn
                        .frame(width: 148, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                OtterTile {
                    processColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            OtterTile(verticalPadding: 6) { footer }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Le relevé ne tourne que pendant que l'onglet est affiché : un `ps`
        // toutes les 5 s en permanence ferait de ce moniteur l'un des coupables.
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: État

    private var stateColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            OtterStatRow(
                icon: thermalIcon,
                iconTint: thermalTint,
                label: "Thermique"
            ) {
                // La température, quand le SMC la donne, à côté de l'état
                // déclaré par macOS : « Normal · 52 °C » se lit d'un coup.
                Text(monitor.sensors?.cpuMax.map { "\(monitor.thermalState.label) · \(Int($0))°" }
                     ?? monitor.thermalState.label)
                    .font(.otterValue)
                    .foregroundStyle(thermalTint)
            }
            OtterStatRow(
                icon: "cpu",
                iconTint: monitor.cpuUsage > 0.8 ? Otter.warning : Otter.textPrimary,
                label: "CPU",
                progress: monitor.cpuUsage,
                progressTint: monitor.cpuUsage > 0.8 ? Otter.warning : Otter.accent
            ) {
                Text("\(Int(monitor.cpuUsage * 100)) %")
                    .font(.otterValue)
                    .foregroundStyle(Otter.textPrimary)
            }
            OtterStatRow(
                icon: "memorychip",
                iconTint: memory.usedFraction > 0.9 ? Otter.warning : Otter.textPrimary,
                label: "Mémoire",
                progress: memory.usedFraction,
                progressTint: memory.usedFraction > 0.9 ? Otter.warning : Otter.accent
            ) {
                Text("\(Int(memory.usedFraction * 100)) %")
                    .font(.otterValue)
                    .foregroundStyle(Otter.textPrimary)
            }
            // Le verdict plutôt que l'état : « Redémarrage conseillé » dit quoi
            // faire, « Normal » ne dit rien. Le clic mène au détail.
            Button(action: { onOpenWindow?() }) {
                HStack(alignment: .top, spacing: 4) {
                    Circle()
                        .fill(verdictTint)
                        .frame(width: 5, height: 5)
                        .padding(.top, 3)
                    Text(verdict.title)
                        .font(.otterMicro)
                        .foregroundStyle(verdict.severity >= .advice ? Otter.textPrimary : Otter.textTertiary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .help(verdict.subtitle)
        }
    }

    private var verdict: HealthAdvisor.Verdict {
        HealthAdvisor.verdict(for: HealthAdvisor.findings(
            monitor: monitor, memory: memory, battery: battery,
            history: settings.monitorHistoryEnabled ? history : nil
        ))
    }

    private var verdictTint: Color {
        switch verdict.severity {
        case .info: return Otter.positive
        case .advice: return Otter.accent
        case .warning: return Otter.warning
        case .critical: return Otter.danger
        }
    }

    private var thermalIcon: String {
        switch monitor.thermalState {
        case .nominal: return "thermometer.low"
        case .fair: return "thermometer.medium"
        default: return "thermometer.high"
        }
    }

    private var thermalTint: Color {
        switch monitor.thermalState {
        case .nominal: return Otter.positive
        case .fair: return Otter.textPrimary
        case .serious: return Otter.warning
        default: return Otter.danger
        }
    }

    // MARK: Processus

    private var processColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LES PLUS GOURMANDS")
                .font(.otterMicro)
                .tracking(0.6)
                .foregroundStyle(Otter.textTertiary)

            if monitor.apps.isEmpty {
                Text("Relevé en cours…")
                    .font(.otterLabel)
                    .foregroundStyle(Otter.textTertiary)
            } else {
                // Par APPLICATION et non par processus : « Google Chrome 84 % »
                // se comprend, cinq « Google Chrome Helper » à 17 % non.
                ForEach(monitor.apps.prefix(4)) { app in
                    appRow(app)
                }
            }
        }
    }

    private func appRow(_ app: AppUsage) -> some View {
        HStack(spacing: 8) {
            Text(app.name)
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            if app.processCount > 1 {
                Text("×\(app.processCount)")
                    .font(.otterMicro)
                    .foregroundStyle(Otter.textTertiary)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Text(app.memoryText)
                .font(.otterMicro)
                .foregroundStyle(Otter.textTertiary)
                .lineLimit(1)
                .fixedSize()
            Text("\(Int(app.cpu)) %")
                .font(.otterValue)
                .foregroundStyle(app.cpu > 80 ? Otter.warning : Otter.textPrimary)
                .lineLimit(1)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 16)
        .help("\(app.name) — \(app.processCount) processus, PID \(app.id)")
    }

    private func processRow(_ process: SystemMonitor.ProcessUsage) -> some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
                // Troncature en FIN et non au milieu : « Google Chrome Help… »
                // se lit, « Googl…Helper » non.
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            // lineLimit + fixedSize sur les DEUX valeurs : sans ça « 1 234 Mo »
            // s'enroulait sur deux lignes, chaque rangée enflait, et la tuile
            // du bas se retrouvait poussée hors de la carte.
            Text("\(Int(process.memoryMB)) Mo")
                .font(.otterMicro)
                .foregroundStyle(Otter.textTertiary)
                .lineLimit(1)
                .fixedSize()
            // Pourcentage d'UN cœur : au-delà de 100 %, le processus occupe
            // plusieurs cœurs, ce qui est justement le cas intéressant.
            Text("\(Int(process.cpu)) %")
                .font(.otterValue)
                .foregroundStyle(process.cpu > 80 ? Otter.warning : Otter.textPrimary)
                .lineLimit(1)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 16)
        // Le nom est tronqué faute de place : l'infobulle donne l'entier, avec
        // le PID pour aller le retrouver dans le Moniteur d'activité.
        .help("\(process.name) — PID \(process.id)")
    }

    // MARK: Actions

    private var footer: some View {
        HStack(spacing: 6) {
            OtterActionLink(title: "Rapport .md", icon: "square.and.arrow.down", tint: Otter.accent) {
                let markdown = DiagnosticReport.build(
                    monitor: monitor,
                    memory: memory,
                    battery: battery,
                    showBattery: showBattery,
                    history: settings.monitorHistoryEnabled ? history : nil
                )
                savedReport = DiagnosticReport.save(markdown)
            }
            if let savedReport {
                OtterActionLink(title: "Révéler", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([savedReport])
                }
            }
            if let onOpenWindow {
                OtterActionLink(title: "En grand", icon: "macwindow", action: onOpenWindow)
            }
            OtterActionLink(title: "Actualiser", icon: "arrow.clockwise") {
                monitor.refresh()
                memory.refresh()
            }
            Spacer(minLength: 0)
            if let date = monitor.lastRefresh {
                Text(Self.time.string(from: date))
                    .font(.otterMicro)
                    .foregroundStyle(Otter.textTertiary)
            }
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
