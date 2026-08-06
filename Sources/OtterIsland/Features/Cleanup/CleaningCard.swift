import SwiftUI
import AppKit

/// Carte affichée dans l'encoche pendant le nettoyage : rappelle que le clavier
/// est verrouillé, et propose le seul moyen de le déverrouiller (un clic — pas
/// le clavier, qui est justement bloqué).
struct CleaningCard: View {
    let permissionDenied: Bool
    var onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                OtterIconBadge(
                    icon: "keyboard.badge.ellipsis",
                    tint: permissionDenied ? Otter.danger : Otter.warning
                )
                Text(permissionDenied ? "Verrouillage impossible" : "Clavier verrouillé")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Otter.textPrimary)
            }

            if permissionDenied {
                if AppInstall.needsRelocation {
                    // Cause racine n°1 : app lancée hors de /Applications → App
                    // Translocation → identité TCC mouvante → permissions cochées
                    // mais jamais appliquées. Tout le reste est inutile tant que
                    // ce n'est pas réglé.
                    Text("L'app tourne depuis \(AppInstall.humanLocation) : macOS lui donne une identité différente à chaque lancement, les permissions ne peuvent PAS s'appliquer. Installe-la d'abord dans /Applications.")
                        .font(.otterMeta)
                        .foregroundStyle(Otter.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    OtterActionLink(title: "Installer dans /Applications et relancer", icon: "arrow.down.app", tint: Otter.accent) {
                        AppInstall.installInApplications()
                    }
                }

                // Bloquer les frappes demande DEUX autorisations distinctes : Accessibilité
                // ET Surveillance des saisies. Cocher seulement la première (l'erreur la
                // plus fréquente) ne suffit pas — d'où l'état en direct de chacune, et
                // le redémarrage nécessaire pour qu'une autorisation nouvellement
                // accordée soit prise en compte.
                permissionStatus(
                    "Accessibilité",
                    granted: Paster.hasAccessibility
                )
                permissionStatus(
                    "Surveillance des saisies",
                    granted: CGPreflightListenEventAccess()
                )
                Text("Après avoir coché (ou re-coché) : redémarre OtterIsland — la permission n'est lue qu'au lancement. Signature ad-hoc oblige, macOS peut re-décocher à chaque mise à jour.")
                    .font(.otterMeta)
                    .foregroundStyle(Otter.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    OtterActionLink(title: "Accessibilité", icon: "figure.wave", tint: Otter.warning) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    OtterActionLink(title: "Surveillance des saisies", icon: "keyboard", tint: Otter.warning) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Spacer(minLength: 0)
                }

                // Une permission d'event tap n'est lue qu'au lancement du
                // processus : sans redémarrage, « j'ai tout autorisé et ça ne
                // marche toujours pas ». Ce bouton enlève cette friction.
                OtterActionLink(title: "Redémarrer OtterIsland", icon: "arrow.clockwise", tint: Otter.accent) {
                    Self.relaunch()
                }
            } else {
                Text("Nettoie tranquillement, aucune frappe ne passe.")
                    .font(.otterMeta)
                    .foregroundStyle(Otter.textSecondary)
            }

            // Seule sortie du mode nettoyage : elle doit se voir, pas se deviner.
            Button(action: onUnlock) {
                Text(permissionDenied ? "Fermer" : "Déverrouiller")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OtterPillButtonStyle(prominent: !permissionDenied))
        }
    }

    /// Ligne d'état d'une permission : ✓ verte ou ✗ rouge, lisible en direct.
    private func permissionStatus(_ name: String, granted: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(granted ? Otter.positive : Otter.danger)
            Text(name)
                .font(.otterMeta)
                .foregroundStyle(Otter.textPrimary)
        }
    }

    /// Relance une nouvelle instance puis quitte celle-ci.
    private static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}
