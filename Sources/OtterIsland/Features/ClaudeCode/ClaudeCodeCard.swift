import SwiftUI

/// Carte affichée dans l'encoche quand Claude Code attend une décision.
struct ClaudeCodeCard: View {
    let request: ActionRequest
    let onDecision: (Bool) -> Void
    /// Notification (rien à décider) : un seul bouton OK.
    var onDismiss: () -> Void = {}

    var body: some View {
        OtterTile(horizontalPadding: 12, verticalPadding: 10) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    OtterIconBadge(icon: request.isNotice ? "bell.fill" : "brain", tint: Otter.warning)
                    Text(request.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        // Chasse négative sur le grand texte : les lettres se
                        // desserrent optiquement quand le corps grandit.
                        .tracking(Otter.trackingTitle)
                        .foregroundStyle(Otter.textPrimary)
                        .lineLimit(2)
                }

                if let detail = request.detail {
                    Text(detail)
                        .font(.otterMeta)
                        .foregroundStyle(Otter.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if request.isNotice {
                    Button(action: onDismiss) {
                        Text("OK").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OtterPillButtonStyle(prominent: true))
                } else {
                    HStack(spacing: 8) {
                        Button {
                            onDecision(false)
                        } label: {
                            Text("Refuser")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OtterPillButtonStyle())

                        Button {
                            onDecision(true)
                        } label: {
                            Text("Approuver")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OtterPillButtonStyle(prominent: true))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
