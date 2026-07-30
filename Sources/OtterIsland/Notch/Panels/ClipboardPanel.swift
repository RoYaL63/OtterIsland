import SwiftUI
import AppKit

/// Panneau Presse-papier : historique récent, clic pour coller dans l'app active.
struct ClipboardPanel: View {
    @ObservedObject var clipboard: ClipboardManager
    let onPick: (ClipboardItem) -> Void

    @State private var hovered: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sans Accessibilité, le clic ne peut pas coller tout seul : le dire
            // ICI, à l'endroit exact où l'utilisateur constate le problème.
            if AppInstall.needsRelocation {
                // Cause racine : hors de /Applications, la permission ne peut
                // même pas s'appliquer (App Translocation, identité mouvante).
                Button {
                    AppInstall.installInApplications()
                } label: {
                    Label("App hors /Applications — installer et relancer", systemImage: "exclamationmark.triangle.fill")
                        .font(.otterBody)
                        .foregroundStyle(Otter.danger)
                }
                .buttonStyle(.plain)
                .help("Lancée depuis \(AppInstall.humanLocation), les permissions ne s'appliquent jamais. Clique pour l'installer dans /Applications.")
            } else if !Paster.hasAccessibility {
                Button {
                    Paster.ensureAccessibility()
                } label: {
                    Label("Activer le collage au clic (Accessibilité)", systemImage: "exclamationmark.triangle.fill")
                        .font(.otterBody)
                        .foregroundStyle(Otter.warning)
                }
                .buttonStyle(.plain)
                .help("Sans cette permission, l'item est copié mais il faut faire ⌘V soi-même. Redémarre l'app après l'avoir cochée.")
            }
            if clipboard.items.isEmpty {
                OtterEmptyState(
                    icon: "doc.on.clipboard",
                    title: "Presse-papier vide",
                    subtitle: "Copie quelque chose, ça apparaîtra ici."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(clipboard.items) { item in
                            itemRow(item)
                        }
                    }
                }
                OtterDivider(axis: .horizontal)
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

    private func itemRow(_ item: ClipboardItem) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(spacing: 8) {
                if let data = item.imageData, let image = NSImage(data: data) {
                    thumbnail(image)
                    Text("Image")
                        .font(.otterBody)
                        .foregroundStyle(Otter.textPrimary)
                } else if let url = item.fileURL {
                    FileThumbnail(url: url, size: CGSize(width: 30, height: 20))
                    Text("Capture d'écran")
                        .font(.otterBody)
                        .foregroundStyle(Otter.textPrimary)
                } else if let text = item.text {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Otter.textSecondary)
                        .frame(width: 30)
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
                RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous)
                    .fill(hovered == item.id ? Color.white.opacity(0.10) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
    }

    private func thumbnail(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 30, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous)
                    .stroke(Otter.chipStroke, lineWidth: 0.5)
            )
    }
}
