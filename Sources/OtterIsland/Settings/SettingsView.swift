import SwiftUI

/// Fenêtre de réglages (⌘,). Simple pour l'instant, s'étoffe avec les modules.
struct SettingsView: View {
    @EnvironmentObject var settings: OtterSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var selectedScreenID: String = {
        guard let screen = NSScreen.main else { return "built-in" }
        return ScreenIdentifier.stableID(for: screen)
    }()

    var body: some View {
        TabView {
            general
                .tabItem { Label("Général", systemImage: "gearshape") }
            notch
                .tabItem { Label("Encoche", systemImage: "macbook") }
            about
                .tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 320)
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
            Text("Clique pour enregistrer une nouvelle combinaison. Redémarre OtterIsland après changement.")
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

            Toggle("Aperçu des captures d'écran dans l'encoche", isOn: $settings.screenshotPreviewEnabled)
            Text("Redémarre OtterIsland après changement.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        VStack(spacing: 10) {
            Text("🦦 OtterIsland")
                .font(.title2.weight(.semibold))
            Text("Version 0.1.0 — MIT")
                .foregroundStyle(.secondary)
            Text("Une encoche vivante avec une loutre et une inbox Claude Code.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
