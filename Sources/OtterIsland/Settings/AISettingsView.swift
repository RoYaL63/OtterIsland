import SwiftUI
import AppKit

/// Page « Assistants IA » : quels assistants suivre (tokens, session en
/// cours), et le branchement de leurs demandes dans l'île.
struct AISettingsView: View {
    @EnvironmentObject var settings: OtterSettings
    @State private var claudeHookInstalled = AIHookInstaller.isClaudeHookInstalled
    @State private var codexScriptReady = AIHookInstaller.isCodexScriptReady
    @State private var errorMessage: String?
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.aiClaudeCodeEnabled) {
                    Text("Suivre Claude Code")
                    Text("Temps actif, conversations, tokens et temps par projet, sur le jour, 7 jours ou 30 jours. Lu dans ~/.claude/projects, sur ce Mac : rien n'est envoyé nulle part, et les journaux ne sont relus que quand tu ouvres l'onglet.")
                }
                installStatus(.claudeCode)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Demandes dans l'île")
                        Spacer()
                        if claudeHookInstalled {
                            Label("branché", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Débrancher") { run { try AIHookInstaller.uninstallClaudeHook() } }
                        } else {
                            Button("Brancher") { run { try AIHookInstaller.installClaudeHook() } }
                        }
                    }
                    caption("« Claude veut utiliser Bash », « Claude attend ta réponse » : ces messages apparaissent dans l'onglet Assistants IA (sous-menu Demandes, avec une pastille sur l'onglet), sans jamais bloquer le reste de l'île. Tu peux les approuver, les refuser ou les ignorer ; elles disparaissent seules après une heure. La loutre lève la tête. « Brancher » ajoute un hook Notification à ~/.claude/settings.json (une copie de sauvegarde est faite à côté, settings.json.otterisland-backup) ; il vaut pour les nouvelles sessions. Tu réponds toujours dans Claude Code, l'île te prévient.")
                }
            } header: {
                Text("Claude Code")
            }

            Section {
                Toggle(isOn: $settings.aiCodexEnabled) {
                    HStack(spacing: 6) {
                        Text("Suivre Codex")
                        Text("non testé")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(.orange)
                    }
                    Text("Temps actif, conversations, tokens et projets, lus dans ~/.codex/sessions. Écrit d'après la documentation de Codex CLI, sans avoir pu l'essayer : dis-nous si les chiffres te semblent faux.")
                }
                installStatus(.codex)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Fin de tâche dans l'île")
                        Spacer()
                        if codexScriptReady {
                            Label("script prêt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Préparer le script") { run { try AIHookInstaller.prepareCodexScript() } }
                        }
                    }
                    caption("Codex peut lancer un programme à la fin de chaque tâche. Ajoute cette ligne dans ~/.codex/config.toml (OtterIsland ne modifie pas ce fichier lui-même) :")
                    HStack {
                        Text(AIHookInstaller.codexConfigLine)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                        Button(copied ? "Copié" : "Copier") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AIHookInstaller.codexConfigLine, forType: .string)
                            copied = true
                        }
                    }
                }
            } header: {
                Text("Codex")
            }

            Section {
                caption("L'app ChatGPT ne laisse ni sa consommation ni ses demandes lisibles sur le Mac : impossible de la suivre depuis l'île.")
            } header: {
                Text("ChatGPT")
            }

            Section {
                Toggle(isOn: $settings.claudeCodeInboxEnabled) {
                    Text("Inbox par dossier")
                    Text("Pour tes propres scripts : un fichier JSON déposé dans ~/.otterisland/inbox s'affiche dans l'île avec Approuver / Refuser. Format dans docs/CLAUDE_CODE.md.")
                }
            } header: {
                Text("Avancé")
            } footer: {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func installStatus(_ assistant: AIAssistant) -> some View {
        if !assistant.isInstalled {
            caption("\(assistant.name) n'a pas encore de sessions sur ce Mac (dossier \(assistant.logsURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) introuvable).")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch {
            errorMessage = "Échec : \(error.localizedDescription)"
        }
        claudeHookInstalled = AIHookInstaller.isClaudeHookInstalled
        codexScriptReady = AIHookInstaller.isCodexScriptReady
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
