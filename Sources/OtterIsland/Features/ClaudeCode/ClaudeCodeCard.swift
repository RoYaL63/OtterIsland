import SwiftUI

/// Carte affichée dans l'encoche quand Claude Code attend une décision.
struct ClaudeCodeCard: View {
    let request: ActionRequest
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text(request.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            if let detail = request.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    onDecision(false)
                } label: {
                    Text("Refuser")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(tint: .white.opacity(0.22), fg: .white))

                Button {
                    onDecision(true)
                } label: {
                    Text("Approuver")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(tint: .orange, fg: .black))
            }
        }
    }
}

private struct PillButtonStyle: ButtonStyle {
    let tint: Color
    let fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .liquidGlassBackground(in: Capsule(), tint: tint)
            .foregroundStyle(fg)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
