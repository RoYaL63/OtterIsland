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
    let showBattery: Bool

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
                Text(monitor.thermalState.label)
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
            // Ce que le système FAIT à cet état vaut mieux que l'état seul.
            Text(monitor.thermalState.explanation)
                .font(.otterMicro)
                .foregroundStyle(Otter.textTertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
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

            if monitor.topByCPU.isEmpty {
                Text("Relevé en cours…")
                    .font(.otterLabel)
                    .foregroundStyle(Otter.textTertiary)
            } else {
                ForEach(monitor.topByCPU.prefix(4)) { process in
                    processRow(process)
                }
            }
        }
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
                    showBattery: showBattery
                )
                savedReport = DiagnosticReport.save(markdown)
            }
            if let savedReport {
                OtterActionLink(title: "Révéler", icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([savedReport])
                }
            }
            OtterActionLink(title: "Actualiser", icon: "arrow.clockwise") {
                monitor.refresh()
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
