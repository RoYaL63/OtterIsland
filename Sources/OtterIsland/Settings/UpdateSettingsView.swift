import SwiftUI

/// Onglet « Mise à jour » des réglages : vérifier, télécharger, installer et
/// relancer sans quitter l'app.
struct UpdateSettingsView: View {
    @ObservedObject var updater: Updater
    @EnvironmentObject var settings: OtterSettings

    var body: some View {
        Form {
            LabeledContent("Version installée") {
                Text(updater.currentVersion).font(.callout.monospacedDigit())
            }

            Section {
                statusRow
            }

            Toggle("Vérifier au lancement", isOn: $settings.autoCheckUpdates)

            Divider()

            // Le point qui fait toute la différence pour l'utilisateur : est-ce
            // qu'il va devoir re-cocher ses permissions après la mise à jour ?
            // Autant répondre avant, pas après.
            LabeledContent("Permissions après mise à jour") {
                if Updater.signatureIsStable {
                    Text("✓ conservées")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("à re-cocher")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text(Updater.signatureIsStable
                 ? "Cette build est signée avec une identité stable : macOS reconnaît la même app d'une version à l'autre et garde tes autorisations."
                 : "Cette build est signée en ad-hoc : macOS lui attribue une identité différente à chaque version et redemande donc l'Accessibilité et la Surveillance des saisies. Correctif côté CI, voir docs/SIGNING.md.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("La mise à jour remplace l'app à son emplacement actuel et ne passe pas par la quarantaine Gatekeeper : plus besoin de `spctl --add` ni de glisser le zip à la main.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link("Voir toutes les versions sur GitHub", destination: updater.releasesPageURL)
                .font(.caption)
        }
        .padding()
        .onAppear {
            if case .idle = updater.state { updater.check() }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch updater.state {
        case .idle:
            Button("Vérifier maintenant") { updater.check() }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Recherche…").font(.callout)
            }

        case .upToDate:
            HStack(spacing: 8) {
                Text("✓ OtterIsland est à jour")
                    .font(.callout)
                    .foregroundStyle(.green)
                Spacer()
                Button("Revérifier") { updater.check() }
            }

        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version \(release.version) disponible")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button("Installer et redémarrer") { updater.install(release) }
                        .keyboardShortcut(.defaultAction)
                }
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(release.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 90)
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text("Téléchargement…").font(.callout)
                ProgressView(value: progress)
            }

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installation, l'app va redémarrer…").font(.callout)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Réessayer") { updater.check() }
                    Link("Télécharger à la main", destination: updater.releasesPageURL)
                        .font(.caption)
                }
            }
        }
    }
}
