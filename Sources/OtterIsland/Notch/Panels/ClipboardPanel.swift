import SwiftUI
import AppKit

/// Panneau Presse-papier : historique récent, clic pour coller dans l'app active.
struct ClipboardPanel: View {
    @ObservedObject var clipboard: ClipboardManager
    let onPick: (ClipboardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Sans Accessibilité, le clic ne peut pas coller tout seul : le dire
            // ICI, à l'endroit exact où l'utilisateur constate le problème.
            if !Paster.hasAccessibility {
                Button {
                    Paster.ensureAccessibility()
                } label: {
                    Label("Activer le collage au clic (Accessibilité)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Sans cette permission, l'item est copié mais il faut faire ⌘V soi-même.")
            }
            if clipboard.items.isEmpty {
                Text("Presse-papier vide")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Copie quelque chose, ça apparaîtra ici.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(clipboard.items) { item in
                            itemRow(item)
                        }
                    }
                }
                Button { clipboard.clear() } label: {
                    Text("Vider").font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
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
                        .font(.caption)
                        .foregroundStyle(.white)
                } else if let url = item.fileURL {
                    FileThumbnail(url: url)
                    Text("Capture d'écran")
                        .font(.caption)
                        .foregroundStyle(.white)
                } else if let text = item.text {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 30)
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func thumbnail(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 30, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.25), lineWidth: 0.5))
    }
}

/// Vignette d'un item « fichier » (capture d'écran), chargée hors du corps de la
/// vue pour ne pas décoder l'image à chaque passe de rendu de la liste.
private struct FileThumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 30, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.25), lineWidth: 0.5))
        .task(id: url) {
            image = NSImage(contentsOf: url)
        }
    }
}
