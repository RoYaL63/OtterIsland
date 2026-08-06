import SwiftUI
import AppKit

/// Panneau Captures : la dernière en grand, les précédentes en bande dessous.
///
/// Avant, c'était une grille de vignettes de 46 pt toutes identiques : impossible
/// de voir ce qu'on venait de capturer sans ouvrir Aperçu, et rien ne distinguait
/// la dernière des autres. Maintenant la capture sélectionnée (la plus récente
/// par défaut) occupe une vraie place, encadrée en aqua, avec ses actions ;
/// cliquer une vignette de la bande la fait monter en grand.
struct ScreenshotsPanel: View {
    @ObservedObject var screenshot: ScreenshotWatcher
    /// Remet la capture dans le presse-papier système, prête pour ⌘V.
    let onCopy: (URL) -> Void

    /// Capture affichée en grand. nil = la plus récente (suit automatiquement
    /// les nouvelles captures au lieu de rester figée sur un ancien choix).
    @State private var picked: URL?
    @State private var justCopied: URL?

    private var selected: URL? {
        if let picked, screenshot.history.contains(picked) { return picked }
        return screenshot.history.first
    }

    var body: some View {
        Group {
            if let selected {
                VStack(alignment: .leading, spacing: 8) {
                    OtterTile { hero(selected) }
                    if screenshot.history.count > 1 {
                        OtterTile(horizontalPadding: 8, verticalPadding: 5) {
                            HStack(alignment: .center, spacing: 8) {
                                filmstrip
                                OtterActionLink(title: "Vider", tint: Otter.textTertiary) {
                                    screenshot.clearHistory()
                                    picked = nil
                                }
                            }
                        }
                    }
                }
            } else {
                OtterTile {
                    OtterEmptyState(
                        icon: "camera.viewfinder",
                        title: "Aucune capture",
                        subtitle: "⌘⇧4 — elle apparaît ici, déjà copiée pour ⌘V."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Capture en grand

    private func hero(_ url: URL) -> some View {
        // 104 et pas 124 : la colonne de droite doit loger trois pastilles
        // d'action (« Copier », « Ouvrir », « Retirer » ≈ 197 pt à elles trois).
        // À 124, il manquait 2 pt et les trois libellés se faisaient tronquer
        // en « Cop… », « Ouv… », « Retir… ».
        HStack(alignment: .top, spacing: 9) {
            FileThumbnail(url: url, size: CGSize(width: 104, height: 78), cornerRadius: Otter.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous)
                        .stroke(Otter.accent.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 7, y: 3)
                .onDrag { NSItemProvider(object: url as NSURL) }
                .help("Glisse-la où tu veux")

            VStack(alignment: .leading, spacing: 6) {
                if url == screenshot.history.first {
                    Text("Dernière")
                        .font(.otterMicro)
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            ZStack {
                                Capsule().fill(Otter.accentGradient)
                                SpecularRim(shape: Capsule(), strength: 0.8, lineWidth: 0.75)
                            }
                        )
                }
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.otterBody)
                    .foregroundStyle(Otter.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    OtterActionLink(
                        title: justCopied == url ? "Copiée" : "Copier",
                        icon: justCopied == url ? "checkmark" : "doc.on.doc",
                        tint: justCopied == url ? Otter.accent : Otter.textSecondary
                    ) {
                        onCopy(url)
                        justCopied = url
                    }
                    OtterActionLink(title: "Ouvrir", icon: "arrow.up.forward.app") {
                        NSWorkspace.shared.open(url)
                    }
                    Spacer(minLength: 0)
                    OtterActionLink(title: "Retirer", icon: "trash", tint: Otter.textTertiary) {
                        screenshot.remove(url)
                        picked = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: 78)
        // Le badge « Copiée » retombe quand on change de capture.
        .onChange(of: url) { _, _ in justCopied = nil }
    }

    // MARK: Bande des précédentes

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(screenshot.history, id: \.self) { url in
                    Button { picked = url } label: {
                        FileThumbnail(url: url, size: CGSize(width: 52, height: 34), cornerRadius: Otter.Radius.small)
                            .overlay(
                                RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous)
                                    .stroke(
                                        url == selected ? Otter.accent : .clear,
                                        lineWidth: 1.5
                                    )
                            )
                            .opacity(url == selected ? 1 : 0.7)
                    }
                    .buttonStyle(.plain)
                    .help(url.lastPathComponent)
                    .onDrag { NSItemProvider(object: url as NSURL) }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 40)
    }
}
