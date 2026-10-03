import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Bande qui affiche les raccourcis tapés pendant le Live (« ⌘ ⇧ 4 »), pour
/// que les participants suivent la démo.
///
/// Seuls les RACCOURCIS s'affichent — une touche avec ⌘, ⌃ ou ⌥, ou Échap.
/// Jamais le texte tapé : un mot de passe saisi pendant une démo finirait
/// sinon en grosses lettres au milieu de l'écran.
@MainActor
final class KeystrokeHUD: ObservableObject {
    @Published private(set) var keys: [String] = []

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ keys: [String], position: LiveKeysPosition, scale: Double) {
        self.keys = keys
        let panel = panel ?? makePanel()
        self.panel = panel

        let size = CGSize(width: 520 * scale, height: 74 * scale)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let y = position == .bottom ? visible.minY + 40 : visible.maxY - size.height - 70
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        }
        if let host = panel.contentView as? NSHostingView<KeystrokeStrip> {
            host.rootView = KeystrokeStrip(hud: self, scale: scale)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    panel.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated { panel.orderOut(nil) }
                }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 74),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: KeystrokeStrip(hud: self, scale: 1))
        return panel
    }

    // MARK: Lecture d'un événement clavier

    /// Libellés à afficher pour cette frappe, ou nil si ce n'est pas un raccourci.
    static func labels(for event: NSEvent) -> [String]? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShortcut = flags.contains(.command) || flags.contains(.control) || flags.contains(.option)
        let keyCode = Int(event.keyCode)
        guard isShortcut || keyCode == kVK_Escape else { return nil }

        var out: [String] = []
        if flags.contains(.control) { out.append("⌃") }
        if flags.contains(.option) { out.append("⌥") }
        if flags.contains(.shift) { out.append("⇧") }
        if flags.contains(.command) { out.append("⌘") }

        if let special = specialKeys[keyCode] {
            out.append(special)
        } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            out.append(chars)
        } else {
            return nil
        }
        return out
    }

    private static let specialKeys: [Int: String] = [
        kVK_Escape: "esc", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Space: "espace", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

struct KeystrokeStrip: View {
    @ObservedObject var hud: KeystrokeHUD
    let scale: Double

    var body: some View {
        HStack(spacing: 7 * scale) {
            ForEach(Array(hud.keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 22 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12 * scale)
                    .padding(.vertical, 6 * scale)
                    .frame(minWidth: 40 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .shadow(color: .black.opacity(0.35), radius: 0, y: 2)
                    )
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 10 * scale)
        .background(
            RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                .fill(Color.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 16 * scale, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
