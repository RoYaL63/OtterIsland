import SwiftUI
import AppKit

/// Guide de l'app : raccourcis, fonctionnement, fonctionnalités, permissions.
/// Affiché dans la fenêtre « À propos » (menu de la loutre) et dans l'onglet
/// À propos des réglages.
struct AboutView: View {
    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                section("Comment ça marche", icon: "macbook") {
                    row("cursorarrow.motionlines", "Survole l'encoche", "La carte s'ouvre ; elle se replie quand la souris ressort. Encoche repliée, les clics passent au travers, rien n'est bloqué.")
                    row("scroll", "Molette au-dessus de l'encoche", "Vers le bas pour ouvrir, vers le haut pour fermer (désactivable dans les réglages).")
                    row("pawprint.fill", "La loutre est un indicateur vivant", "Elle nage quand la musique joue, halète quand la RAM sature, s'inquiète batterie faible, passe le chiffon pendant le nettoyage, dort quand rien ne se passe.")
                    row("cursorarrow.click.2", "Clic gauche sur 🦦 (barre de menus)", "Ouvre directement le presse-papier dans l'encoche. Clic droit : ce menu.")
                }

                section("Raccourcis", icon: "keyboard") {
                    row("option", "⌥V — Presse-papier", "Depuis n'importe quel champ de texte : l'historique s'ouvre sans voler le focus, clique un item (texte ou capture) → collé directement. Modifiable dans les réglages.")
                    row("command", "⌘, — Réglages", "Depuis la fenêtre de réglages ouverte.")
                    row("square.and.arrow.down", "Glisser un fichier sur l'encoche", "L'ouvre sur l'Étagère pour le déposer (puis AirDrop ou glisser ailleurs).")
                }

                section("Fonctionnalités", icon: "sparkles") {
                    row("doc.on.clipboard", "Presse-papier", "Historique des 30 derniers éléments copiés. Chaque capture d'écran y entre automatiquement — ⌥V, clic, collée.")
                    row("camera.viewfinder", "Captures", "Chaque capture part directement dans le presse-papier (⌘⇧4 puis ⌘V). Aperçu transitoire sous l'encoche, onglet dédié avec la dernière en grand et les précédentes en bande, glisser-déposer vers une autre app.")
                    row("calendar", "Agenda", "Mini calendrier navigable (clic sur un jour → ses réunions), prochains RDV, lien visio cliquable, rappels à cocher.")
                    row("music.note", "Musique", "Spotify / Apple Music : titre, contrôles, la loutre nage en rythme.")
                    row("memorychip", "Système", "RAM (pression colorée), batterie et temps restant, minuteur Pomodoro.")
                    row("sparkles", "Nettoyage clavier", "Petite icône 🧽 de l'accueil : verrouille TOUTES les frappes pour nettoyer, l'encoche reste grande, seul le clic Déverrouiller libère.")
                    row("camera.fill", "Miroir", "La caméra en petit, pour se recoiffer avant une visio.")
                    row("terminal.fill", "Inbox Claude Code", "Une demande de validation Claude Code apparaît dans l'encoche, approuve ou refuse d'un clic (~/.otterisland/inbox).")
                }

                section("Installation et mise à jour", icon: "arrow.down.circle") {
                    row("externaldrive.fill.badge.plus", "Installeur .dmg", "Ouvre le .dmg, glisse la loutre sur Applications. Si tu la lances d'ailleurs, elle propose de s'y installer toute seule au premier lancement.")
                    row("arrow.down.circle", "Depuis l'app", "Réglages › Mise à jour : OtterIsland télécharge la nouvelle version, remplace l'app à sa place et redémarre. Pas de zip, pas de quarantaine Gatekeeper, pas de spctl.")
                    row("lock.shield", "Et les permissions ?", "Elles ne survivent que si les builds sont signées avec une identité stable — l'onglet Mise à jour le dit franchement. Voir docs/SIGNING.md.")
                }

                section("Permissions — le mode d'emploi", icon: "lock.shield") {
                    row("folder.badge.questionmark", "D'abord : /Applications", "Lancée d'ailleurs (Téléchargements…), macOS change l'identité de l'app à chaque lancement : les permissions cochées ne s'appliquent JAMAIS. Le diagnostic des réglages le signale.")
                    row("figure.wave", "Accessibilité", "Pour le collage automatique au clic (⌘V simulé).")
                    row("keyboard.badge.ellipsis", "Surveillance des saisies", "Pour le verrouillage clavier du mode nettoyage.")
                    row("calendar.badge.checkmark", "Calendrier et Rappels", "Pour l'agenda dans l'encoche.")
                    row("gearshape.arrow.triangle.2.circlepath", "Automatisation", "Pour lire l'état de Spotify / Apple Music.")
                    row("arrow.clockwise", "Après avoir coché : relancer l'app", "Une permission n'est lue qu'au lancement. Et après une mise à jour (signature ad-hoc), macOS peut re-décocher : − puis + dans le panneau concerné.")
                }

                Text("Open source (MIT) — github.com/RoYaL63/OtterIsland")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("OtterIsland")
                    .font(.title2.weight(.semibold))
                Text("Version \(Self.version) — une encoche vivante avec une loutre de compagnie")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Fenêtre « À propos » indépendante, ouverte depuis le menu de la loutre.
@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        let win = window ?? makeWindow()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingView(rootView: AboutView())
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "À propos d'OtterIsland"
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.center()
        return win
    }
}
