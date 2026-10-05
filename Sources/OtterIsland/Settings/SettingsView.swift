import SwiftUI

/// Page des réglages, dans l'ordre du sommaire.
enum SettingsTab: Hashable, CaseIterable, Identifiable {
    case general, features, appearance, notch, clipboard, screenshots, monitor, permissions, focus, update, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "Général"
        case .features: return "Fonctionnalités"
        case .appearance: return "Apparence"
        case .notch: return "Encoche et écrans"
        case .clipboard: return "Presse-papier"
        case .screenshots: return "Captures d'écran"
        case .monitor: return "Moniteur"
        case .permissions: return "Autorisations"
        case .focus: return "Concentration"
        case .update: return "Mise à jour"
        case .about: return "À propos"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .features: return "switch.2"
        case .appearance: return "paintpalette"
        case .notch: return "macbook"
        case .clipboard: return "doc.on.clipboard"
        case .screenshots: return "camera.viewfinder"
        case .monitor: return "gauge.with.dots.needle.33percent"
        case .permissions: return "lock.shield"
        case .focus: return "moon.fill"
        case .update: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
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

    /// Sommaire à gauche, page à droite, comme les Réglages Système. Les
    /// onglets en haut ne tenaient plus dans la largeur : macOS en cachait la
    /// moitié derrière un bouton « » ».
    var body: some View {
        HStack(spacing: 0) {
            List(selection: tabSelection) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            page(router.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 460, idealHeight: 560)
    }

    /// `List` veut une sélection optionnelle ; le routeur, lui, a toujours une page.
    private var tabSelection: Binding<SettingsTab?> {
        Binding(
            get: { router.tab },
            set: { if let tab = $0 { router.tab = tab } }
        )
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: general
        case .features: FeaturesSettingsView()
        case .appearance: AppearanceSettingsView()
        case .notch: notch
        case .clipboard: clipboard
        case .screenshots: screenshots
        case .monitor: monitor
        case .permissions: PermissionsSettingsView()
        case .focus: FocusSettingsView()
        case .update: UpdateSettingsView(updater: updater)
        case .about: about
        }
    }

    private var general: some View {
        Form {
            Section("Démarrage") {
                Toggle("Lancer au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        launchAtLoginError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled // resynchronise avec le vrai statut
                        launchAtLoginNeedsApproval = LaunchAtLogin.needsApproval
                    }
                if let error = launchAtLoginError {
                    caption(error, color: .red)
                } else if launchAtLoginNeedsApproval {
                    caption("Approuve OtterIsland dans Réglages Système › Général › Éléments de connexion.", color: .orange)
                }
            }

            // L'ouverture intempestive est le reproche n°1 : ces deux réglages
            // vivent en haut de l'onglet, pas noyés en bas.
            Section("Ouverture de l'île") {
                Toggle("Ouvrir au survol de l'encoche", isOn: $settings.hoverToOpen)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Temps d'arrêt avant ouverture : \(String(format: "%.2f", settings.hoverOpenDelay)) s")
                    Slider(value: $settings.hoverOpenDelay, in: 0.1...1.5, step: 0.05)
                    caption("Le pointeur doit rester IMMOBILE sur l'encoche pendant ce temps. Traverser la zone pour aller cliquer ailleurs — un onglet de navigateur, par exemple — n'ouvre rien, quelle que soit la lenteur du geste. Et après une fermeture, il faut ressortir de la zone avant de pouvoir rouvrir.")
                }
                .disabled(!settings.hoverToOpen)
                toggle("Contrôle à la molette",
                       "Molette vers le bas au-dessus de l'encoche pour l'ouvrir, vers le haut pour fermer.",
                       isOn: $settings.gestureControl)
            }


        }
        .formStyle(.grouped)
    }

    private var clipboard: some View {
        Form {
            Section {
                Toggle("Presse-papier (raccourci global)", isOn: $settings.clipboardEnabled)
                LabeledContent("Raccourci d'ouverture") {
                    ShortcutRecorderView(
                        keyCode: $settings.clipboardHotKeyCode,
                        modifiers: $settings.clipboardHotKeyModifiers
                    )
                }
                caption("⌥V par défaut : ouvre l'historique depuis n'importe quel champ de texte, clique un item (texte ou capture d'écran) pour le coller. Clique pour enregistrer une nouvelle combinaison. Redémarre OtterIsland après changement.")
                if settings.clipboardHotKeyRegistrationFailed {
                    caption("Cette combinaison n'a pas pu être enregistrée (déjà prise par une autre app ou le système) — la frappe passe telle quelle. Choisis-en une autre.", color: .red)
                }
                Button("Autoriser l'Accessibilité (collage auto)") {
                    Paster.ensureAccessibility()
                }
            }

        }
        .formStyle(.grouped)
    }

    private var screenshots: some View {
        Form {
            Section {
                Toggle("Notification des captures d'écran (en bas à droite)", isOn: $settings.screenshotPreviewEnabled)
                toggle("Copier la capture dans le presse-papier",
                       "⌘⇧4 puis ⌘V directement : `screencapture` n'écrit que sur le disque, OtterIsland met la capture dans le presse-papier. Redémarre OtterIsland après changement de l'aperçu.",
                       isOn: $settings.screenshotAutoCopy)
                // LA cause du « ça met très longtemps » : tant que la vignette Apple
                // est à l'écran, le fichier n'existe pas encore sur le disque.
                Toggle("Vignette flottante de macOS", isOn: floatingThumbnailBinding)
                caption(floatingThumbnail
                        ? "Active : après ⌘⇧4, macOS garde la capture ~5 s le temps d'afficher sa vignette en bas à droite, et n'écrit le fichier qu'ensuite. Tant qu'elle est là, AUCUNE app ne peut voir la capture — d'où l'attente avant qu'elle arrive dans le presse-papier. Décoche pour que ce soit immédiat : la notification d'OtterIsland la remplace (clic pour modifier, glisser, copier)."
                        : "Désactivée : la capture est écrite tout de suite, la notification et le presse-papier suivent dans la foulée. S'applique dès la prochaine capture.",
                        color: floatingThumbnail ? .orange : .secondary)
            }

        }
        .formStyle(.grouped)
    }

    private var monitor: some View {
        Form {
            Section {
                Toggle("Suivre ce qui ralentit le Mac au fil des jours", isOn: $settings.monitorHistoryEnabled)
                Toggle("Noter les pages web lors des emballements", isOn: $settings.monitorRecordPageTitles)
                    .disabled(!settings.monitorHistoryEnabled)
            } footer: {
                caption("Un relevé par minute, gardé 14 jours, uniquement sur ce Mac. Alimente l'onglet Historique et le diagnostic du Moniteur.")
            }
        }
        .formStyle(.grouped)
    }

    private var notch: some View {
        Form {
            Section {
                Picker("Afficher l'île sur", selection: $settings.islandScreenMode) {
                    ForEach(IslandScreenMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                if settings.islandScreenMode == .fixed {
                    Picker("Écran", selection: $settings.islandFixedScreenID) {
                        Text("Écran du MacBook (par défaut)").tag("")
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            Text(ScreenIdentifier.label(for: screen))
                                .tag(ScreenIdentifier.stableID(for: screen))
                        }
                    }
                }
            } header: {
                Text("Écran de l'île")
            } footer: {
                caption(settings.islandScreenMode.detail + " Sur un écran sans encoche, l'île se replie en un onglet 🦦 au milieu de la barre des menus : survole-le ou clique-le pour l'ouvrir.")
            }

            Section {
                Picker("Écran à régler", selection: $selectedScreenID) {
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(ScreenIdentifier.label(for: screen))
                            .tag(ScreenIdentifier.stableID(for: screen))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ajustement largeur : \(Int(settings.widthOffset(for: selectedScreenID))) pt")
                    Slider(value: widthBinding, in: -40...40, step: 1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Débordement carte étendue : \(Int(settings.dropOffset(for: selectedScreenID))) pt")
                    Slider(value: dropBinding, in: 0...80, step: 1)
                }
            } header: {
                Text("Taille de l'île")
            } footer: {
                caption("Ajuste la taille de l'île écran par écran ; pour choisir OÙ elle s'affiche, c'est la section du dessus. La largeur ne concerne que les écrans à encoche. Redémarre l'affichage après un changement de largeur.")
            }
        }
        .formStyle(.grouped)
    }

    /// Interrupteur avec son explication en sous-titre. Dans un formulaire
    /// groupé, macOS l'affiche sous le titre et la fait passer à la ligne ; en
    /// rangée séparée, l'ancienne mise en page la tronquait au bord droit.
    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }

    /// Texte d'aide : petit, secondaire, et qui passe TOUJOURS à la ligne au
    /// lieu de finir en « … ».
    private func caption(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
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
