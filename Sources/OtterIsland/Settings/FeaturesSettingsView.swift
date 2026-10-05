import SwiftUI

/// Page « Fonctionnalités » : ce que l'île affiche, et dans quel ordre.
/// Onglets (visibles, ordre), éléments de l'accueil, options de l'onglet
/// Musique, bulle de volume, loutre…
struct FeaturesSettingsView: View {
    @EnvironmentObject var settings: OtterSettings

    var body: some View {
        Form {
            Section {
                ForEach(Array(settings.orderedTabs.enumerated()), id: \.element) { index, tab in
                    tabRow(tab, index: index, count: settings.orderedTabs.count)
                }
            } header: {
                Text("Onglets de l'île")
            } footer: {
                caption("Décoche un onglet pour le retirer de la barre ; les flèches le déplacent. Le presse-papier (⌥V) et l'étagère (fichier glissé sur l'encoche) restent accessibles même masqués.")
            }

            Section {
                ForEach(HomeItem.allCases) { item in
                    Toggle(isOn: homeBinding(item)) {
                        Label(item.title, systemImage: item.icon)
                    }
                }
                Toggle(isOn: $settings.showBattery) {
                    Label("Batterie", systemImage: "battery.75percent")
                }
            } header: {
                Text("Accueil")
            } footer: {
                caption("Ce qui s'affiche sur l'onglet Accueil. Un module retiré laisse sa place aux autres.")
            }

            Section("Musique") {
                toggle("Volume et coupure du son",
                       "Curseur de volume du Mac et bouton pour couper le son, à gauche des commandes de lecture.",
                       isOn: $settings.musicShowVolume)
                toggle("Bouton pour ouvrir l'app",
                       "Ouvre Spotify ou Musique depuis l'onglet ; quand rien ne joue, propose de les lancer.",
                       isOn: $settings.musicShowOpenApp)
                toggle("Suivi musique (la loutre nage)",
                       "Lit l'état de Spotify / Apple Music. macOS demandera l'autorisation Automatisation.",
                       isOn: $settings.musicFollow)
            }

            Section("Dans l'île") {
                toggle("Bulle de volume",
                       "Affiche le volume dans l'encoche quand il change. macOS affiche déjà la sienne : coupe celle-ci pour éviter le doublon.",
                       isOn: $settings.volumeHUDEnabled)
                toggle("Loutre de compagnie",
                       "Une petite loutre animée dans la rangée des onglets, qui réagit à ce qui se passe sur ton Mac.",
                       isOn: $settings.otterEnabled)
                toggle("Inbox Claude Code",
                       "L'inbox surveille ~/.otterisland/inbox pour les demandes d'action.",
                       isOn: $settings.claudeCodeInboxEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func tabRow(_ tab: NotchTab, index: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: tabBinding(tab)) {
                Label(tab.title, systemImage: tab.icon)
            }
            .toggleStyle(.checkbox)
            Spacer()
            Button { settings.moveTab(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Déplacer vers la gauche dans la barre")
            Button { settings.moveTab(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == count - 1)
                .help("Déplacer vers la droite dans la barre")
        }
        .buttonStyle(.borderless)
    }

    private func tabBinding(_ tab: NotchTab) -> Binding<Bool> {
        Binding(
            get: { settings.isTabVisible(tab) },
            set: { settings.setTab(tab, visible: $0) }
        )
    }

    private func homeBinding(_ item: HomeItem) -> Binding<Bool> {
        Binding(
            get: { settings.isHomeItemVisible(item) },
            set: { settings.setHomeItem(item, visible: $0) }
        )
    }

    private func toggle(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
