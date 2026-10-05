import SwiftUI

/// Onglet « Assistants IA » de l'île : pour chaque assistant suivi, les
/// tokens du jour, la session en cours et son projet. Les demandes en attente
/// (permission, tâche terminée) passent, elles, par la carte prioritaire de
/// l'inbox, quel que soit l'onglet affiché.
struct AIPanel: View {
    @ObservedObject var monitor: AIUsageMonitor
    @EnvironmentObject private var settings: OtterSettings
    let onOpenSettings: () -> Void

    var body: some View {
        let assistants = settings.enabledAssistants
        Group {
            if assistants.isEmpty {
                OtterTile {
                    VStack(spacing: 8) {
                        OtterEmptyState(
                            icon: "brain",
                            title: "Aucun assistant suivi",
                            subtitle: "Choisis Claude Code ou Codex pour suivre tokens et demandes."
                        )
                        OtterActionLink(title: "Choisir les assistants", icon: "gear", tint: Otter.accent, action: onOpenSettings)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(assistants) { assistant in
                        AssistantTile(
                            assistant: assistant,
                            snapshot: monitor.snapshots[assistant],
                            compact: assistants.count > 1
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { monitor.refresh() }
    }
}

private struct AssistantTile: View {
    let assistant: AIAssistant
    let snapshot: AIUsageSnapshot?
    /// Deux assistants côte à côte : moins de détail par tuile.
    let compact: Bool

    var body: some View {
        OtterTile(horizontalPadding: 12, verticalPadding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                header
                if !assistant.isInstalled {
                    Text("Introuvable sur ce Mac : aucun dossier de sessions.")
                        .font(.otterMeta)
                        .foregroundStyle(Otter.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let snapshot {
                    counts(snapshot)
                } else {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            OtterIconBadge(icon: assistant.icon, tint: snapshot?.isActive == true ? Otter.accent : Otter.textSecondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(assistant.name)
                    .font(.otterTitle)
                    .foregroundStyle(Otter.textPrimary)
                Text(statusText)
                    .font(.otterMeta)
                    .foregroundStyle(snapshot?.isActive == true ? Otter.accent : Otter.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var statusText: String {
        guard let snapshot, let last = snapshot.lastActivity else { return "Pas d'activité aujourd'hui" }
        if snapshot.isActive {
            return snapshot.sessionProject.map { "En cours · \($0)" } ?? "En cours"
        }
        return "Dernière activité " + Self.relative.localizedString(for: last, relativeTo: Date())
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()

    @ViewBuilder
    private func counts(_ snapshot: AIUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Aujourd'hui", snapshot.today, emphasized: true)
            if snapshot.lastActivity != nil {
                row(compact ? "Session" : "Dernière session", snapshot.sessionTokens, emphasized: false)
            }
        }
    }

    /// « Aujourd'hui   1,2 M » puis le détail entrée / sortie / cache.
    private func row(_ label: String, _ tokens: TokenCount, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.otterLabel)
                    .foregroundStyle(Otter.textSecondary)
                Spacer(minLength: 4)
                Text(TokenCount.format(tokens.total))
                    .font(emphasized ? .otterValue : .otterBody)
                    .monospacedDigit()
                    .foregroundStyle(Otter.textPrimary)
                Text("tokens")
                    .font(.otterMeta)
                    .foregroundStyle(Otter.textTertiary)
            }
            // Deux tuiles côte à côte : le détail ne tient pas, le total suffit.
            if !compact {
                Text("entrée \(TokenCount.format(tokens.input)) · sortie \(TokenCount.format(tokens.output)) · cache \(TokenCount.format(tokens.cached))")
                    .font(.otterMeta)
                    .foregroundStyle(Otter.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}
