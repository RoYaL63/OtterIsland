import SwiftUI

/// Carte affichée dans l'encoche quand Claude Code attend une décision.
struct ClaudeCodeCard: View {
    let request: ActionRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Otter.warning)
                Text(request.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Otter.textPrimary)
                    .lineLimit(1)
            }

            if let detail = request.detail {
                Text(detail)
                    .font(.otterMeta)
                    .foregroundStyle(Otter.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    onDecision(false)
                } label: {
                    Text("Refuser")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(tint: Color.white.opacity(0.14), fg: Otter.textPrimary))

                Button {
                    onDecision(true)
                } label: {
                    Text("Approuver")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(tint: Otter.accent, fg: .black.opacity(0.82)))
            }
        }
    }
}

private struct PillButtonStyle: ButtonStyle {
    let tint: Color
    let fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .chipBackground(in: Capsule(), tint: tint)
            .foregroundStyle(fg)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
