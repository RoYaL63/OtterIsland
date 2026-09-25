import AppKit
import SwiftUI

/// Fenêtre « Moniteur » : la version longue de l'onglet de l'encoche.
///
/// La carte de l'encoche doit rester lisible d'un coup d'œil ; le détail —
/// toutes les applications, leurs processus, leurs fenêtres, et de quoi les
/// arrêter — demande de la place. D'où une vraie fenêtre, ouverte à la demande.
@MainActor
final class MonitorWindowController {
    private var window: NSWindow?

    private let monitor: SystemMonitor
    private let memory: MemoryMonitor
    private let battery: BatteryMonitor
    private let history: UsageHistory
    private let settings: OtterSettings

    init(
        monitor: SystemMonitor, memory: MemoryMonitor, battery: BatteryMonitor,
        history: UsageHistory, settings: OtterSettings
    ) {
        self.monitor = monitor
        self.memory = memory
        self.battery = battery
        self.history = history
        self.settings = settings
    }

    func show() {
        let win = window ?? makeWindow()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = MonitorWindowView(monitor: monitor, memory: memory, battery: battery, history: history)
            .environmentObject(settings)
        let host = NSHostingView(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Moniteur — OtterIsland"
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.center()
        return win
    }
}

/// Sections de la fenêtre. Le diagnostic d'abord : c'est la réponse à « que
/// dois-je faire ? », les autres onglets en sont le détail.
enum MonitorSection: String, CaseIterable, Identifiable {
    case diagnosis = "Diagnostic"
    case memory = "Mémoire"
    case heat = "Chaleur"
    case apps = "Applications"
    case history = "Historique"

    var id: String { rawValue }
}

struct MonitorWindowView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var memory: MemoryMonitor
    @ObservedObject var battery: BatteryMonitor
    @ObservedObject var history: UsageHistory
    @EnvironmentObject var settings: OtterSettings

    @State private var section: MonitorSection = .diagnosis
    /// Application dépliée. Une seule à la fois : ouvrir la suivante referme la
    /// précédente, sinon la liste devient un mur.
    @State private var expanded: pid_t?
    @State private var savedReport: URL?

    private var findings: [HealthAdvisor.Finding] {
        HealthAdvisor.findings(monitor: monitor, memory: memory, battery: battery,
                               history: settings.monitorHistoryEnabled ? history : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $section) {
                ForEach(MonitorSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Divider()
            Group {
                switch section {
                case .diagnosis:
                    MonitorDiagnosisView(findings: findings)
                case .memory:
                    MonitorMemoryView(monitor: monitor, memory: memory)
                case .heat:
                    MonitorHeatView(monitor: monitor, battery: battery)
                case .apps:
                    list
                case .history:
                    MonitorHistoryView(history: history)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .onAppear {
            monitor.start()
            memory.refresh()
        }
        .onDisappear { monitor.stop() }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 18) {
            metric("Thermique", monitor.thermalState.label, tint: thermalTint)
            if let temp = monitor.sensors?.cpuMax {
                metric("Puce", "\(Int(temp)) °C", tint: temp >= 90 ? .orange : .primary)
            }
            metric("CPU", "\(Int(monitor.cpuUsage * 100)) %", tint: monitor.cpuUsage > 0.8 ? .orange : .primary)
            metric("Mémoire", "\(Int(memory.usedFraction * 100)) %", tint: memory.pressure != .normal ? .orange : .primary)
            if let fan = monitor.sensors?.fans.first {
                metric("Ventilateur", "\(Int(fan.rpm)) tr/min", tint: fan.level >= 0.6 ? .orange : .primary)
            }
            Spacer()
            verdictBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var verdictBadge: some View {
        let verdict = HealthAdvisor.verdict(for: findings)
        return HStack(spacing: 6) {
            Image(systemName: verdict.severity >= .warning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
            Text(verdict.title).lineLimit(1)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(MonitorStyle.tint(verdict.severity))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(MonitorStyle.tint(verdict.severity).opacity(0.12)))
        .help(verdict.subtitle)
        .onTapGesture { section = .diagnosis }
    }

    private func metric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }

    private var thermalTint: Color {
        switch monitor.thermalState {
        case .nominal: return .green
        case .fair: return .primary
        case .serious: return .orange
        default: return .red
        }
    }

    // MARK: Liste

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.apps.prefix(30)) { app in
                    appRow(app)
                    if expanded == app.id {
                        detail(app)
                    }
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func appRow(_ app: AppUsage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: expanded == app.id ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10)
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "gearshape.2")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.body).lineLimit(1)
                let known = app.isGUI ? nil : KnownProcesses.info(for: app.name)
                if known != nil || app.processCount > 1 {
                    Text([known?.label, app.processCount > 1 ? "\(app.processCount) processus" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(app.memoryText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text("\(Int(monitor.share(of: app) * 100)) % du total")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
            Text("\(Int(app.cpu)) %")
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(app.cpu > 80 ? .orange : .primary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            expanded = (expanded == app.id) ? nil : app.id
        }
    }

    // MARK: Détail déplié

    @ViewBuilder
    private func detail(_ app: AppUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            explanations(app)
            windowsSection(app)

            if app.processCount > 1 {
                Text("PROCESSUS").font(.caption2).foregroundStyle(.tertiary)
                ForEach(app.processes.prefix(8)) { process in
                    HStack(spacing: 8) {
                        Text(process.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 6)
                        Text("PID \(process.id)").font(.caption2).foregroundStyle(.tertiary)
                        Text("\(Int(process.memoryMB)) Mo")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        Text("\(Int(process.cpu)) %")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            HStack(spacing: 8) {
                if app.isGUI {
                    Button("Quitter") { quit(app) }
                }
                Button("Forcer l'arrêt") { confirmForce(app) }
                    .tint(.red)
                Spacer()
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.leading, 28)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }

    /// Ce que sont les processus reconnus : « mds_stores » devient « Spotlight
    /// indexe tes fichiers, ça se calme seul ».
    @ViewBuilder
    private func explanations(_ app: AppUsage) -> some View {
        let known = Dictionary(
            app.processes.compactMap { p in KnownProcesses.info(for: p.name).map { ($0.label, $0) } },
            uniquingKeysWith: { a, _ in a }
        )
        if !known.isEmpty {
            ForEach(known.keys.sorted(), id: \.self) { key in
                if let info = known[key] {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: info.kind == .transient ? "hourglass" : "info.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info.label).font(.caption.weight(.semibold))
                            Text(info.explanation)
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Les titres de fenêtres : c'est ici qu'on lit « quel onglet ». Pour un
    /// navigateur, le titre de fenêtre EST le titre de l'onglet actif.
    @ViewBuilder
    private func windowsSection(_ app: AppUsage) -> some View {
        if !app.isGUI {
            EmptyView()
        } else if !WindowInspector.hasPermission {
            HStack(spacing: 6) {
                Text("Titres des fenêtres indisponibles — autorisation Accessibilité manquante.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Autoriser") { Paster.ensureAccessibility() }
                    .controlSize(.mini)
            }
        } else {
            let titles = WindowInspector.windowTitles(pid: app.id)
            if titles.isEmpty {
                Text("Aucune fenêtre ouverte.").font(.caption).foregroundStyle(.tertiary)
            } else {
                Text("FENÊTRES").font(.caption2).foregroundStyle(.tertiary)
                ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                    HStack(spacing: 6) {
                        Image(systemName: "macwindow").font(.caption2).foregroundStyle(.tertiary)
                        Text(title).font(.caption).lineLimit(1)
                    }
                }
                // Dire ce que ces titres ne disent PAS vaut mieux que de laisser
                // conclure qu'un onglet consomme 80 %.
                Text("Le CPU ci-dessus est celui de toute l'application. Chrome ne publie pas la correspondance entre ses processus et ses onglets — son propre gestionnaire de tâches (Fenêtre › Gestionnaire de tâches) est le seul endroit où elle est lisible.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Actions

    private func quit(_ app: AppUsage) {
        report(ProcessTerminator.quit(pid: app.id), app: app)
    }

    /// Confirmation obligatoire : un SIGKILL perd le travail non enregistré, et
    /// le bouton par défaut reste « Annuler ».
    private func confirmForce(_ app: AppUsage) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Forcer l'arrêt de « \(app.name) » ?"
        alert.informativeText = app.processCount > 1
            ? "Ses \(app.processCount) processus seront tués immédiatement. Le travail non enregistré sera perdu."
            : "Le processus sera tué immédiatement. Le travail non enregistré sera perdu."
        alert.addButton(withTitle: "Annuler")
        alert.addButton(withTitle: "Forcer l'arrêt")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        report(ProcessTerminator.force(pid: app.id), app: app)
    }

    private func report(_ outcome: ProcessTerminator.Outcome, app: AppUsage) {
        if case .failed(let message) = outcome {
            let alert = NSAlert()
            alert.messageText = "« \(app.name) » n'a pas pu être arrêtée"
            alert.informativeText = message
            alert.runModal()
        }
        expanded = nil
        monitor.refresh()
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Rapport .md") {
                savedReport = DiagnosticReport.save(
                    DiagnosticReport.build(
                        monitor: monitor, memory: memory,
                        battery: battery, showBattery: true,
                        history: settings.monitorHistoryEnabled ? history : nil
                    )
                )
            }
            if let savedReport {
                Button("Révéler") {
                    NSWorkspace.shared.activateFileViewerSelecting([savedReport])
                }
            }
            Button("Actualiser") {
                monitor.refresh()
                memory.refresh()
            }
            Spacer()
            Text("Relevé toutes les 5 s")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
