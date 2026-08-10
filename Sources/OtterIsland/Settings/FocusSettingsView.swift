import SwiftUI

/// Onglet « Concentration » : durées du Pomodoro et ce qu'il déclenche.
///
/// Le minuteur ne faisait que décompter. Cet onglet est l'endroit où on décide
/// ce qu'une session PROVOQUE — mise en Concentration du Mac, musique coupée,
/// son de fin — parce que c'est là que se trouve la vraie valeur d'un Pomodoro :
/// pas dans le chiffre qui descend, dans le silence qu'il installe.
struct FocusSettingsView: View {
    @EnvironmentObject var settings: OtterSettings

    /// Raccourcis de l'utilisateur, relus à chaque ouverture de l'onglet : il
    /// vient peut-être d'en créer un dans l'app Raccourcis, à côté.
    @State private var shortcuts: [String] = []

    var body: some View {
        Form {
            Section("Durées") {
                Stepper(
                    "Session de travail : \(settings.pomodoroWorkMinutes) min",
                    value: $settings.pomodoroWorkMinutes,
                    in: 5...120,
                    step: 5
                )
                Stepper(
                    settings.pomodoroBreakMinutes == 0
                        ? "Pause : aucune"
                        : "Pause : \(settings.pomodoroBreakMinutes) min",
                    value: $settings.pomodoroBreakMinutes,
                    in: 0...30,
                    step: 1
                )
                Toggle("Enchaîner la pause automatiquement", isOn: $settings.pomodoroAutoStartBreak)
                    .disabled(settings.pomodoroBreakMinutes == 0)
            }

            Section("Pendant une session") {
                focusShortcutRow(
                    title: "Activer la Concentration",
                    selection: $settings.pomodoroFocusShortcutOn
                )
                focusShortcutRow(
                    title: "La couper à la fin",
                    selection: $settings.pomodoroFocusShortcutOff
                )
                explanation
                Toggle("Mettre la musique en pause", isOn: $settings.pomodoroPauseMusic)
                Toggle("Son à la fin de chaque phase", isOn: $settings.pomodoroChime)
                Text("Un son plutôt qu'une notification : une bannière percerait justement la Concentration que la session vient d'activer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcuts = FocusMode.availableShortcuts() }
    }

    /// Menu des raccourcis existants. Un menu et pas un champ texte : un nom mal
    /// orthographié échouerait en silence au moment le moins pratique.
    private func focusShortcutRow(title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Aucun").tag("")
            ForEach(shortcuts, id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .disabled(shortcuts.isEmpty)
    }

    @ViewBuilder
    private var explanation: some View {
        if !FocusMode.isSupported {
            Text("L'outil `shortcuts` est introuvable sur ce Mac : la mise en Concentration automatique n'est pas disponible.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if shortcuts.isEmpty {
            // Le cas de loin le plus fréquent au premier lancement : aucun
            // raccourci n'existe, donc le menu est vide et sans explication on
            // croirait la fonctionnalité cassée.
            VStack(alignment: .leading, spacing: 6) {
                Text("Aucun raccourci trouvé. macOS ne laisse aucune app activer la Concentration directement — seule l'app Raccourcis en a le droit. Crée deux raccourcis avec l'action « Définir la concentration » (l'un qui l'active, l'autre qui la désactive), ils apparaîtront ici.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Ouvrir Raccourcis") { FocusMode.openShortcutsApp() }
                    Button("Actualiser la liste") { shortcuts = FocusMode.availableShortcuts() }
                }
                .font(.caption)
            }
        } else {
            HStack {
                Text("Ces raccourcis viennent de l'app Raccourcis : c'est le seul moyen sanctionné par macOS d'activer la Concentration depuis une app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Actualiser") { shortcuts = FocusMode.availableShortcuts() }
                    .font(.caption)
            }
        }
    }
}
