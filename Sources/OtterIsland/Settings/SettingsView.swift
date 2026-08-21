import SwiftUI

/// Onglet affiché à l'ouverture des réglages.
enum SettingsTab: Hashable {
    case general, notch, focus, update, about
}

/// Qui commande l'onglet ouvert. Vit en dehors de la vue, dans l'AppDelegate :
/// « Rechercher les mises à jour… » doit POUVOIR ouvrir les réglages sur
/// l'onglet Mise à jour, et un `@State` interne à la vue ne se pilote pas de
/// l'extérieur. C'est ce qui manquait : le menu lançait bien la vérification,
/// mais la fenêtre s'ouvrait sur Général et la version disponible restait
/// invisible, deux clics plus loin.
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Fenêtre de réglages (⌘,). Simple pour l'instant, s'étoffe avec les modules.
struct SettingsView: View {
    @EnvironmentObject var settings: OtterSettings
    @EnvironmentObject var router: SettingsRouter
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var floatingThumbnail = SystemScreenshotSettings.floatingThumbnailEnabled
    @State private var selectedScreenID: String = {
        guard let screen = NSScreen.main else { return "built-in" }
        return ScreenIdentifier.stableID(for: screen)
    }()

    var body: some View {
        TabView(selection: $router.tab) {
            general
                .tabItem { Label("Général", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            notch
                .tabItem { Label("Encoche", systemImage: "macbook") }
                .tag(SettingsTab.notch)
            FocusSettingsView()
                .tabItem { Label("Concentration", systemImage: "moon.fill") }
                .tag(SettingsTab.focus)
            UpdateSettingsView(updater: updater)
                .tabItem { Label("Mise à jour", systemImage: "arrow.down.circle") }
                .tag(SettingsTab.update)
            about
                .tabItem { Label("À propos", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 440, height: 340)
    }

    private var general: some View {
        Form {
            Toggle("Lancer au démarrage", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    launchAtLoginError = LaunchAtLogin.set(enabled)
                    launchAtLogin = LaunchAtLogin.isEnabled // resynchronise avec le vrai statut
                    launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
                }
            if let error = launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if launchAtLoginNeedsApproval {
                Text("Approuve OtterIsland dans Réglages Système › Général › Éléments de connexion.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            // L'ouverture intempestive est le reproche n°1 : ces deux réglages
            // vivent en haut de l'onglet, pas noyés en bas.
            Toggle("Ouvrir au survol de l'encoche", isOn: $settings.hoverToOpen)
            VStack(alignment: .leading) {
                Text("Temps d'arrêt avant ouverture : \(String(format: "%.2f", settings.hoverOpenDelay)) s")
                Slider(value: $settings.hoverOpenDelay, in: 0.1...1.5, step: 0.05)
            }
            .disabled(!settings.hoverToOpen)
            Text("Le pointeur doit rester IMMOBILE sur l'encoche pendant ce temps. Traverser la zone pour aller cliquer ailleurs — un onglet de navigateur, par exemple — n'ouvre rien, quelle que soit la lenteur du geste. Et après une fermeture, il faut ressortir de la zone avant de pouvoir rouvrir.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Loutre de compagnie", isOn: $settings.otterEnabled)
            Toggle("Afficher la batterie", isOn: $settings.showBattery)
            Toggle("Inbox Claude Code", isOn: $settings.claudeCodeInboxEnabled)
            Text("L'inbox surveille ~/.otterisland/inbox pour les demandes d'action.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Suivi musique (la loutre nage)", isOn: $settings.musicFollow)
            Text("Lit l'état de Spotify / Apple Music. macOS demandera l'autorisation Automatisation.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Contrôle à la molette", isOn: $settings.gestureControl)
            Text("Molette vers le bas au-dessus de l'encoche pour l'ouvrir, vers le haut pour fermer.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Presse-papier (raccourci global)", isOn: $settings.clipboardEnabled)
            HStack {
                Text("Raccourci d'ouverture")
                Spacer()
                ShortcutRecorderView(
                    keyCode: $settings.clipboardHotKeyCode,
                    modifiers: $settings.clipboardHotKeyModifiers
                )
            }
            Text("⌥V par défaut : ouvre l'historique depuis n'importe quel champ de texte, clique un item (texte ou capture d'écran) pour le coller. Clique pour enregistrer une nouvelle combinaison. Redémarre OtterIsland après changement.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.clipboardHotKeyRegistrationFailed {
                Text("Cette combinaison n'a pas pu être enregistrée (déjà prise par une autre app ou le système) — la frappe passe telle quelle. Choisis-en une autre.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Autoriser l'Accessibilité (collage auto)") {
                Paster.ensureAccessibility()
            }
            .font(.caption)

            Divider()

            // Diagnostic permissions : l'endroit où comprendre pourquoi le
            // verrouillage clavier ou le collage auto ne répond pas.
            LabeledContent("Emplacement") {
                if AppInstall.needsRelocation {
                    Button("Hors /Applications — installer et relancer") {
                        AppInstall.installInApplications()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .help("Lancée depuis \(AppInstall.humanLocation), les permissions ne s'appliquent jamais (App Translocation).")
                } else {
                    Text("✓ /Applications").font(.caption).foregroundStyle(.green)
                }
            }
            LabeledContent("Accessibilité (collage auto)") {
                Text(Paster.hasAccessibility ? "✓ accordée" : "✗ manquante")
                    .font(.caption)
                    .foregroundStyle(Paster.hasAccessibility ? .green : .red)
            }
            LabeledContent("Surveillance des saisies (verrouillage)") {
                Text(CGPreflightListenEventAccess() ? "✓ accordée" : "✗ manquante")
                    .font(.caption)
                    .foregroundStyle(CGPreflightListenEventAccess() ? .green : .red)
            }
            Text("Une permission cochée n'est lue qu'au prochain lancement de l'app. Après une mise à jour (signature ad-hoc), macOS peut la re-décocher : − puis + dans le panneau correspondant.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Aperçu des captures d'écran dans l'encoche", isOn: $settings.screenshotPreviewEnabled)
            Toggle("Copier la capture dans le presse-papier", isOn: $settings.screenshotAutoCopy)
            Text("⌘⇧4 puis ⌘V directement : `screencapture` n'écrit que sur le disque, OtterIsland met la capture dans le presse-papier. Redémarre OtterIsland après changement de l'aperçu.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // LA cause du « ça met très longtemps » : tant que la vignette Apple
            // est à l'écran, le fichier n'existe pas encore sur le disque.
            Toggle("Vignette flottante de macOS", isOn: floatingThumbnailBinding)
            Text(floatingThumbnail
                 ? "Active : après ⌘⇧4, macOS garde la capture ~5 s le temps d'afficher sa vignette en bas à droite, et n'écrit le fichier qu'ensuite. Tant qu'elle est là, AUCUNE app ne peut voir la capture — d'où l'attente avant qu'elle arrive dans le presse-papier. Décoche pour que ce soit immédiat : l'aperçu d'OtterIsland la remplace (glisser, copier, ouvrir)."
                 : "Désactivée : la capture est écrite tout de suite, l'aperçu de l'encoche et le presse-papier suivent dans la foulée. S'applique dès la prochaine capture.")
                .font(.caption)
                .foregroundStyle(floatingThumbnail ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }

    private var notch: some View {
        Form {
            Picker("Écran", selection: $selectedScreenID) {
                ForEach(NSScreen.screens, id: \.self) { screen in
                    Text(ScreenIdentifier.label(for: screen))
                        .tag(ScreenIdentifier.stableID(for: screen))
                }
            }

            VStack(alignment: .leading) {
                Text("Ajustement largeur : \(Int(settings.widthOffset(for: selectedScreenID))) pt")
                Slider(value: widthBinding, in: -40...40, step: 1)
            }
            VStack(alignment: .leading) {
                Text("Débordement carte étendue : \(Int(settings.dropOffset(for: selectedScreenID))) pt")
                Slider(value: dropBinding, in: 0...80, step: 1)
            }
            Text("Réglages propres à l'écran sélectionné ci-dessus. Redémarre l'affichage après un changement de largeur.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// Miroir de la préférence système `com.apple.screencapture show-thumbnail`.
    /// Le @State local sert uniquement à rafraîchir la vue : la vérité reste
    /// dans les préférences de macOS, relues à l'ouverture des réglages.
    private var floatingThumbnailBinding: Binding<Bool> {
        Binding(
            get: { floatingThumbnail },
            set: { enabled in
                SystemScreenshotSettings.setFloatingThumbnail(enabled)
                floatingThumbnail = enabled
            }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { settings.widthOffset(for: selectedScreenID) },
            set: { settings.setWidthOffset($0, for: selectedScreenID) }
        )
    }

    private var dropBinding: Binding<Double> {
        Binding(
            get: { settings.dropOffset(for: selectedScreenID) },
            set: { settings.setDropOffset($0, for: selectedScreenID) }
        )
    }

    private var about: some View {
        // Guide complet (raccourcis, fonctionnement, permissions) — le même que
        // la fenêtre « À propos » du menu de la loutre.
        AboutView()
    }
}
