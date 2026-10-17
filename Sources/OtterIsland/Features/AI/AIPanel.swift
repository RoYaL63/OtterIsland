import SwiftUI

/// Onglet « Assistants IA » de l'île. Deux sous-menus :
/// - **Statistiques** : temps actif, conversations, tokens, projets ;
/// - **Demandes** : ce que les assistants attendent de toi (permissions,
///   « j'ai terminé »…), que tu approuves, refuses ou ignores.
///
/// Les demandes vivent ICI et nulle part ailleurs : elles ne prennent jamais la
/// place du reste de l'île. Les journaux ne sont relus que quand cet onglet
/// s'affiche (ou au clic sur ↻), jamais en arrière-plan.
struct AIPanel: View {
    @ObservedObject var monitor: AIUsageMonitor
    @ObservedObject var inbox: ClaudeCodeInbox
    @EnvironmentObject private var settings: OtterSettings
    let onOpenSettings: () -> Void

    private enum Segment { case stats, requests }
    @State private var segment: Segment = .stats
    @State private var shown: AIAssistant?

    private var assistants: [AIAssistant] { settings.enabledAssistants }
    private var current: AIAssistant? {
        if let shown, assistants.contains(shown) { return shown }
        return assistants.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topBar
            Group {
                switch segment {
                case .stats: statsBody
                case .requests: requestsBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            monitor.refresh()
            // Des demandes attendent : c'est ce qu'on vient voir.
            if !inbox.requests.isEmpty { segment = .requests }
        }
    }

    // MARK: Barre du haut

    private var topBar: some View {
        HStack(spacing: 6) {
            pill("Stats", selected: segment == .stats) { segment = .stats }
            pill("Demandes", selected: segment == .requests, badge: inbox.requests.count) { segment = .requests }
            Spacer(minLength: 4)
            if segment == .stats {
                ForEach(AIPeriod.allCases) { period in
                    pill(period.shortTitle, selected: settings.aiPeriod == period, compact: true) { settings.aiPeriod = period }
                        .help(period.title)
                }
                Button {
                    monitor.refresh()
                } label: {
                    Group {
                        if monitor.isRefreshing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Otter.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Relire les journaux")
            }
        }
    }

    private func pill(_ title: String, selected: Bool, badge: Int = 0, compact: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: compact ? 10 : 10.5, weight: .semibold)).lineLimit(1).fixedSize()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Otter.warning))
                        .foregroundStyle(Color.black.opacity(0.85))
                }
            }
            .padding(.horizontal, compact ? 7 : 10).padding(.vertical, 4)
            .foregroundStyle(selected ? Otter.onAccent : Otter.textSecondary)
            .background(Capsule().fill(selected ? AnyShapeStyle(Otter.accentGradient) : AnyShapeStyle(Otter.chipFill)))
        }
        .buttonStyle(OtterPressStyle(scale: 0.95))
    }

    // MARK: Statistiques

    @ViewBuilder
    private var statsBody: some View {
        if assistants.isEmpty {
            OtterTile {
                VStack(spacing: 8) {
                    OtterEmptyState(
                        icon: "brain",
                        title: "Aucun assistant suivi",
                        subtitle: "Choisis Claude Code ou Codex pour suivre temps, tokens et projets."
                    )
                    OtterActionLink(title: "Choisir les assistants", icon: "gear", tint: Otter.accent, action: onOpenSettings)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let assistant = current {
            StatsTile(
                assistant: assistant,
                snapshot: monitor.snapshots[assistant]?[settings.aiPeriod],
                assistants: assistants,
                onPick: { shown = $0 }
            )
        }
    }

    // MARK: Demandes

    @ViewBuilder
    private var requestsBody: some View {
        if inbox.requests.isEmpty {
            OtterTile {
                OtterEmptyState(
                    icon: "bell",
                    title: "Aucune demande en attente",
                    subtitle: "Quand Claude Code ou Codex attend quelque chose de toi, ça s'affiche ici — sans bloquer le reste de l'île."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 6) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(inbox.requests.prefix(30)) { request in
                            RequestRow(
                                request: request,
                                onDecision: { inbox.resolve(request, approved: $0) },
                                onDismiss: { inbox.dismiss(request) }
                            )
                        }
                    }
                }
                if inbox.requests.count > 1 {
                    HStack {
                        Spacer()
                        OtterActionLink(title: "Tout ignorer (\(inbox.requests.count))", icon: "xmark.circle", action: { inbox.dismissAll() })
                    }
                }
            }
        }
    }
}

// MARK: - Statistiques d'un assistant

private struct StatsTile: View {
    let assistant: AIAssistant
    let snapshot: AIStatsSnapshot?
    let assistants: [AIAssistant]
    let onPick: (AIAssistant) -> Void

    var body: some View {
        OtterTile(horizontalPadding: 12, verticalPadding: 7) {
            VStack(alignment: .leading, spacing: 6) {
                header
                if !assistant.isInstalled {
                    Text("Introuvable sur ce Mac : aucun dossier de sessions.")
                        .font(.otterMeta).foregroundStyle(Otter.textTertiary)
                } else if let snapshot {
                    content(snapshot)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyse des sessions…").font(.otterMeta).foregroundStyle(Otter.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            OtterIconBadge(icon: assistant.icon, tint: snapshot?.isActive == true ? Otter.accent : Otter.textSecondary, size: 20)
            Text(assistant.name).font(.otterTitle).foregroundStyle(Otter.textPrimary).lineLimit(1).fixedSize()
            Text(status).font(.otterMeta)
                .foregroundStyle(snapshot?.isActive == true ? Otter.accent : Otter.textTertiary)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if assistants.count > 1 {
                HStack(spacing: 4) {
                    ForEach(assistants) { other in
                        Button { onPick(other) } label: {
                            Image(systemName: other.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 22, height: 20)
                                .foregroundStyle(other == assistant ? Otter.onAccent : Otter.textSecondary)
                                .background(Capsule().fill(other == assistant ? AnyShapeStyle(Otter.accentGradient) : AnyShapeStyle(Otter.chipFill)))
                        }
                        .buttonStyle(.plain)
                        .help(other.name)
                    }
                }
            }
        }
    }

    private var status: String {
        guard let snapshot, let last = snapshot.lastActivity else { return "Pas d'activité sur la période" }
        if snapshot.isActive { return snapshot.currentProject.map { "En cours · \($0)" } ?? "En cours" }
        return "Dernière activité " + Self.relative.localizedString(for: last, relativeTo: Date())
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return f
    }()

    @ViewBuilder
    private func content(_ s: AIStatsSnapshot) -> some View {
        if s.sessions == 0, s.tokens.total == 0, s.isComplete {
            Text("Aucune activité sur cette période.").font(.otterMeta).foregroundStyle(Otter.textTertiary)
        } else {
            metrics(s)
            if s.period == .today {
                projects(s, limit: 3, showRest: true)
            } else {
                dailyBars(s)
                projects(s, limit: 2, showRest: false)
            }
        }
    }

    // Temps actif · conversations · tokens
    private func metrics(_ s: AIStatsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 0) {
            metric(AIFormat.duration(s.activeSeconds), "temps actif")
            metric("\(s.sessions)", s.sessions > 1 ? "conversations" : "conversation")
            metric(TokenCount.format(s.tokens.total), "tokens")
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.otterValue).monospacedDigit().foregroundStyle(Otter.textPrimary)
            Text(label).font(.otterMeta).foregroundStyle(Otter.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Temps actif de chaque jour (7 ou 30 jours).
    private func dailyBars(_ s: AIStatsSnapshot) -> some View {
        let peak = max(s.dailyActiveSeconds.max() ?? 0, 1)
        return VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: s.dailyActiveSeconds.count > 14 ? 1.5 : 4) {
                ForEach(Array(s.dailyActiveSeconds.enumerated()), id: \.offset) { index, value in
                    let isToday = index == s.dailyActiveSeconds.count - 1
                    Capsule()
                        .fill(isToday ? Otter.accent : Otter.accent.opacity(0.45))
                        .frame(height: max(2, CGFloat(value / peak) * 20))
                        .frame(maxWidth: .infinity)
                        .help(AIFormat.duration(value))
                }
            }
            .frame(height: 22, alignment: .bottom)
            HStack {
                Text(s.period == .week ? "il y a 7 j" : "il y a 30 j")
                Spacer()
                Text("aujourd'hui")
            }
            .font(.system(size: 8.5)).foregroundStyle(Otter.textTertiary)
        }
    }

    // Projets : nom, barre de temps, temps, tokens.
    private func projects(_ s: AIStatsSnapshot, limit: Int, showRest: Bool) -> some View {
        let top = Array(s.projects.prefix(limit))
        let peak = max(top.map(\.activeSeconds).max() ?? 0, 1)
        return VStack(spacing: 4) {
            ForEach(top) { project in
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.otterBody).foregroundStyle(Otter.textPrimary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Otter.chipFill)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Otter.accent.opacity(0.8))
                                    .frame(width: max(3, geo.size.width * CGFloat(project.activeSeconds / peak)))
                            }
                    }
                    .frame(width: 44, height: 4)
                    Text(AIFormat.duration(project.activeSeconds))
                        .font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Otter.textSecondary)
                        .frame(width: 46, alignment: .trailing)
                    Text(TokenCount.format(project.tokens.total))
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(Otter.textTertiary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
            if showRest, s.projects.count > limit {
                Text("+ \(s.projects.count - limit) autre\(s.projects.count - limit > 1 ? "s" : "")")
                    .font(.otterMeta).foregroundStyle(Otter.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Une demande

private struct RequestRow: View {
    let request: ActionRequest
    let onDecision: (Bool) -> Void
    let onDismiss: () -> Void

    private var age: TimeInterval? { request.createdAt.map { Date().timeIntervalSince($0) } }
    private var isStale: Bool { (age ?? 0) > ClaudeCodeInbox.staleAge }

    var body: some View {
        OtterTile(horizontalPadding: 10, verticalPadding: 8) {
            HStack(alignment: .center, spacing: 8) {
                OtterIconBadge(icon: request.isNotice ? "bell.fill" : "brain", tint: isStale ? Otter.textTertiary : Otter.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(isStale ? Otter.textSecondary : Otter.textPrimary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        if let detail = request.detail {
                            Text(detail).lineLimit(1)
                        }
                        if let age {
                            Text("· " + Self.ageText(age) + (isStale ? " · probablement périmée" : ""))
                                .foregroundStyle(isStale ? Otter.warning : Otter.textTertiary)
                        }
                    }
                    .font(.otterMeta).foregroundStyle(Otter.textTertiary)
                }
                Spacer(minLength: 4)
                actions
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if request.isNotice {
            OtterActionLink(title: "OK", icon: "checkmark", tint: Otter.accent, action: onDismiss)
        } else {
            HStack(spacing: 5) {
                if isStale {
                    // Plus personne n'attend : « Ignorer » passe devant.
                    OtterActionLink(title: "Ignorer", icon: "xmark", tint: Otter.accent, action: onDismiss)
                    OtterActionLink(title: "Refuser", action: { onDecision(false) })
                    OtterActionLink(title: "Approuver", action: { onDecision(true) })
                } else {
                    OtterActionLink(title: "Refuser", action: { onDecision(false) })
                    OtterActionLink(title: "Approuver", icon: "checkmark", tint: Otter.accent, action: { onDecision(true) })
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20).foregroundStyle(Otter.textTertiary).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Ignorer")
                }
            }
        }
    }

    private static func ageText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "à l'instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        return "il y a \(Int(seconds / 3600)) h"
    }
}
