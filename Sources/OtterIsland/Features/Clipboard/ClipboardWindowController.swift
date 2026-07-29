import AppKit
import SwiftUI

/// Fenêtre presse-papier indépendante, ouverte depuis le menu de la barre de
/// statut. Accès fiable qui ne dépend pas du raccourci clavier global (qui
/// peut échouer si la combinaison est déjà prise par une autre app).
@MainActor
final class ClipboardWindowController {
    private var window: NSWindow?
    private let clipboard: ClipboardManager

    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
    }

    func show() {
        let win = window ?? makeWindow()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = ClipboardWindowView(clipboard: clipboard)
        let host = NSHostingView(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Presse-papier — OtterIsland"
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.center()
        return win
    }
}

private struct ClipboardWindowView: View {
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                // Character Viewer natif d'Apple : s'ouvre au-dessus de n'importe
                // quelle app et insère directement dans le champ actif — pas besoin
                // de réinventer un sélecteur d'émoticônes.
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Label("Émoticônes…", systemImage: "face.smiling")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Divider()

            ClipboardPanel(clipboard: clipboard) { item in
                clipboard.restore(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    Paster.paste()
                }
            }
        }
        .padding()
        .frame(minWidth: 280, minHeight: 340)
    }
}
