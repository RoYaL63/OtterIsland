import SwiftUI

/// Carte affichée dans l'encoche pendant le nettoyage : rappelle que le clavier
/// est verrouillé, et propose le seul moyen de le déverrouiller (un clic — pas
/// le clavier, qui est justement bloqué).
struct CleaningCard: View {
    let permissionDenied: Bool
    var onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .foregroundStyle(.orange)
                Text(permissionDenied ? "Verrouillage impossible" : "Clavier verrouillé")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.black)
            }

            if permissionDenied {
                Text("Autorise OtterIsland dans Réglages Système › Confidentialité et sécurité › Accessibilité, puis réessaie.")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.65))
            } else {
                Text("Nettoie tranquillement, aucune frappe ne passe.")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.65))
            }

            Button(action: onUnlock) {
                Text(permissionDenied ? "Fermer" : "Déverrouiller")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .padding(.vertical, 5)
            .foregroundStyle(.black)
            .liquidGlassBackground(in: Capsule(), tint: .black.opacity(0.18))
        }
    }
}
