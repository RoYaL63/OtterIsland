import AppKit

/// Actions rapides pour vibe coder. Chaque action est un simple effet système.
enum QuickActions {
    /// Ouvre Terminal et lance `claude` (Claude Code) dans le dossier courant.
    static func launchClaudeCode() {
        runOsascript(#"tell application "Terminal" to activate"#)
        runOsascript(#"tell application "Terminal" to do script "claude""#)
    }

    /// Ouvre le dossier inbox d'OtterIsland dans le Finder.
    static func openInbox() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".otterisland/inbox")
        NSWorkspace.shared.open(url)
    }

    private static func runOsascript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}
