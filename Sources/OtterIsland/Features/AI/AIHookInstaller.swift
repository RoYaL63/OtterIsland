import Foundation

/// Branche les assistants sur l'inbox d'OtterIsland, pour que leurs demandes
/// (« Claude a besoin de ta permission », « Codex a terminé ») s'affichent
/// dans l'île.
///
/// Le relais est un petit script shell qui recopie tel quel ce que
/// l'assistant lui passe dans `~/.otterisland/inbox` ; l'inbox sait lire ces
/// messages bruts (voir `ClaudeCodeInbox`). Pas de python, pas de jq : rien
/// qui ne soit déjà sur un Mac.
enum AIHookInstaller {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let otterDir = home.appendingPathComponent(".otterisland", isDirectory: true)
    static let claudeScript = otterDir.appendingPathComponent("claude-notify.sh")
    static let codexScript = otterDir.appendingPathComponent("codex-notify.sh")
    /// Réglages de Claude Code. Variable pour pouvoir tester sur une copie.
    static var claudeSettings = home.appendingPathComponent(".claude/settings.json")

    /// Marqueur de nos entrées dans les réglages de Claude Code.
    private static let marker = "claude-notify.sh"

    // MARK: Claude Code

    /// Le hook est-il présent dans ~/.claude/settings.json ?
    static var isClaudeHookInstalled: Bool {
        guard let root = readClaudeSettings(),
              let entries = (root["hooks"] as? [String: Any])?["Notification"] as? [[String: Any]] else { return false }
        return entries.contains(where: isOurs)
    }

    /// Ajoute un hook « Notification » qui relaie les demandes de Claude Code.
    /// Sauvegarde d'abord le fichier tel qu'il était.
    static func installClaudeHook() throws {
        try writeScript(at: claudeScript, body: """
        # Lit le message de Claude Code sur l'entrée standard.
        cat > "$tmp"
        """)
        var root = readClaudeSettings() ?? [:]
        try backupClaudeSettings()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var entries = hooks["Notification"] as? [[String: Any]] ?? []
        entries.removeAll(where: isOurs)
        entries.append(["hooks": [["type": "command", "command": claudeScript.path]]])
        hooks["Notification"] = entries
        root["hooks"] = hooks
        try writeClaudeSettings(root)
    }

    /// Retire nos entrées, sans toucher au reste.
    static func uninstallClaudeHook() throws {
        guard var root = readClaudeSettings(), var hooks = root["hooks"] as? [String: Any],
              var entries = hooks["Notification"] as? [[String: Any]] else { return }
        try backupClaudeSettings()
        entries.removeAll(where: isOurs)
        if entries.isEmpty { hooks["Notification"] = nil } else { hooks["Notification"] = entries }
        if hooks.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
        try writeClaudeSettings(root)
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains(marker) == true } == true
    }

    private static func readClaudeSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeSettings) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func backupClaudeSettings() throws {
        guard FileManager.default.fileExists(atPath: claudeSettings.path) else { return }
        let backup = claudeSettings.deletingLastPathComponent()
            .appendingPathComponent("settings.json.otterisland-backup")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: claudeSettings, to: backup)
    }

    private static func writeClaudeSettings(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: claudeSettings, options: .atomic)
    }

    // MARK: Codex

    /// Ligne à ajouter dans ~/.codex/config.toml. Codex lance ce programme à la
    /// fin de chaque tâche, avec le message en premier argument.
    static var codexConfigLine: String {
        "notify = [\"sh\", \"\(codexScript.path)\"]"
    }

    static var isCodexScriptReady: Bool {
        FileManager.default.isExecutableFile(atPath: codexScript.path)
    }

    static func prepareCodexScript() throws {
        try writeScript(at: codexScript, body: """
        # Codex passe le message en premier argument.
        printf '%s' "$1" > "$tmp"
        """)
    }

    // MARK: Script

    /// Écrit le relais : fichier temporaire puis renommage, pour que l'inbox
    /// ne lise jamais un message à moitié écrit.
    private static func writeScript(at url: URL, body: String) throws {
        let script = """
        #!/bin/sh
        # OtterIsland : relaie un message d'assistant vers l'encoche.
        # Créé par Réglages › Assistants IA. Supprimable sans risque.
        dir="$HOME/.otterisland/inbox"
        mkdir -p "$dir"
        tmp="$dir/.relay-$$.part"
        \(body)
        mv "$tmp" "$dir/relay-$(date +%s)-$$.json"

        """
        try FileManager.default.createDirectory(at: otterDir, withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
