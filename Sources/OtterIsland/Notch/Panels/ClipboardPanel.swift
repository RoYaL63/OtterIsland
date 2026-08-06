import SwiftUI
import AppKit

/// Panneau Presse-papier : historique récent, clic pour coller dans l'app active.
///
/// L'historique vit dans une tuile (le module), l'action « Vider » vit dessous,
/// à l'air libre : dans le système, une action destructrice ne se pose jamais
/// À L'INTÉRIEUR du contenu qu'elle efface.
struct ClipboardPanel: View {
    @ObservedObject var clipboard: ClipboardManager
    let onPick: (ClipboardItem) -> Void

    @State private var hovered: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sans Accessibilité, le clic ne peut pas coller tout seul : le dire
            // ICI, à l'endroit exact où l'utilisateur constate le problème.
            if AppInstall.needsRelocation {
                // Cause racine : hors de /Applications, la permission ne peut
                // même pas s'appliquer (App Translocation, identité mouvante).
                banner(
                    icon: "exclamationmark.triangle.fill",
                    title: "App hors /Applications — installer et relancer",
                    tint: Otter.danger,
                    help: "Lancée depuis \(AppInstall.humanLocation), les permissions ne s'appliquent jamais. Clique pour l'installer dans /Applications."
                ) {
                    AppInstall.installInApplications()
                }
            } else if !Paster.hasAccessibility {
                banner(
                    icon: "exclamationmark.triangle.fill",
                    title: "Activer le collage au clic (Accessibilité)",
                    tint: Otter.warning,
                    help: "Sans cette permission, l'item est copié mais il faut faire ⌘V soi-même. Redémarre l'app après l'avoir cochée."
                ) {
                    Paster.ensureAccessibility()
                }
            }

            if clipboard.items.isEmpty {
                OtterTile {
                    OtterEmptyState(
                        icon: "doc.on.clipboard",
                        title: "Presse-papier vide",
                        subtitle: "Copie quelque chose, ça apparaîtra ici."
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OtterTile(horizontalPadding: 5, verticalPadding: 5) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(clipboard.items) { item in
                                itemRow(item)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    OtterActionLink(title: "Vider", icon: "trash", tint: Otter.textTertiary) {
                        clipboard.clear()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Bandeau d'alerte cliquable, dessiné comme un module : une pastille
    /// d'icône colorée et un libellé blanc. L'ancienne version teintait tout le
    /// texte en rouge, ce qui le rendait moins lisible qu'un texte blanc.
    private func banner(
        icon: String,
        title: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                OtterIconBadge(icon: icon, tint: tint)
                Text(title)
                    .font(.otterBody)
                    .foregroundStyle(Otter.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .glassTile(
                in: RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous),
                fill: tint.opacity(0.16)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func itemRow(_ item: ClipboardItem) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(spacing: 9) {
                if let data = item.imageData, let image = NSImage(data: data) {
                    thumbnail(image)
                    Text("Image")
                        .font(.otterBody)
                        .foregroundStyle(Otter.textPrimary)
                } else if let url = item.fileURL {
                    FileThumbnail(url: url, size: CGSize(width: 32, height: 21))
                    Text("Capture d'écran")
                        .font(.otterBody)
                        .foregroundStyle(Otter.textPrimary)
                } else if let text = item.text {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Otter.textSecondary)
                        .frame(width: 32)
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .font(.otterBody)
                        .foregroundStyle(Otter.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            // Rangée survolée : sans ce fond, rien ne dit qu'une ligne est
            // cliquable, et on ne sait pas laquelle on s'apprête à coller.
            .background(
                RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous)
                    .fill(hovered == item.id ? Otter.tileFillActive : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .animation(Otter.hoverMotion, value: hovered)
    }

    private func thumbnail(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 32, height: 21)
            .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.xsmall, style: .continuous))
            .overlay(
                SpecularRim(
                    shape: RoundedRectangle(cornerRadius: Otter.Radius.xsmall, style: .continuous),
                    strength: 0.7,
                    lineWidth: 0.75
                )
            )
    }
}
