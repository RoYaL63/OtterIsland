import AppKit
import QuartzCore

/// Cache le bureau pendant le Live : une fenêtre posée JUSTE au-dessus des
/// icônes du bureau, mais sous toutes les apps, qui affiche le fond d'écran
/// (ou une couleur unie). Les icônes disparaissent, les fenêtres restent.
///
/// Rien n'est modifié dans le Finder : pas de `defaults write`, pas de
/// redémarrage du Finder. Fermer la fenêtre suffit à tout rendre.
@MainActor
final class DesktopCover {
    private var windows: [NSWindow] = []
    /// Apps masquées par nous, pour ne réafficher que celles-là.
    private var hiddenApps: [NSRunningApplication] = []

    var isShown: Bool { !windows.isEmpty }

    func show(style: LivePreferences) {
        hide(restoreApps: false)
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        for screen in NSScreen.screens {
            let window = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = level
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.hasShadow = false
            window.hidesOnDeactivate = false
            // Les clics sur le « bureau » ne doivent pas atteindre les icônes
            // cachées dessous (on ouvrirait un fichier invisible).
            window.ignoresMouseEvents = false

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.autoresizingMask = [.width, .height]
            if style.desktopCover == .wallpaper,
               let url = NSWorkspace.shared.desktopImageURL(for: screen),
               let image = NSImage(contentsOf: url) {
                view.layer?.contents = image
                view.layer?.contentsGravity = .resizeAspectFill
                view.layer?.backgroundColor = NSColor.black.cgColor
            } else {
                view.layer?.backgroundColor = (NSColor(hex: style.desktopColorHex) ?? .black).cgColor
            }
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }

        if style.hideOtherApps {
            let me = NSRunningApplication.current.processIdentifier
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && !app.isHidden
                && app.processIdentifier != me && app.processIdentifier != front {
                if app.hide() { hiddenApps.append(app) }
            }
        }
    }

    /// - Parameter restoreApps: réaffiche les apps que le Live avait masquées.
    func hide(restoreApps: Bool = true) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if restoreApps {
            hiddenApps.forEach { $0.unhide() }
            hiddenApps = []
        }
    }
}
