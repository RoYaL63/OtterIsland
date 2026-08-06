import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Panneau Étagère : zone de dépôt de fichiers, envoi AirDrop, glisser vers ailleurs.
struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfModel

    @State private var hovered: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shelf.items.isEmpty {
                // La zone de dépôt se dessine comme une zone de dépôt : une
                // tuile en pointillés, pas un texte flottant sur le verre.
                OtterEmptyState(
                    icon: "arrow.down.doc",
                    title: "Dépose des fichiers ici",
                    subtitle: "Ou glisse-les sur l'encoche repliée."
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous)
                        .fill(Otter.tileFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous)
                                .strokeBorder(
                                    Otter.chipStroke,
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                        )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OtterTile(horizontalPadding: 5, verticalPadding: 5) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(shelf.items, id: \.self) { url in
                                itemRow(url)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 8) {
                    OtterActionLink(title: "AirDrop", icon: "shareplay", tint: Otter.accent) {
                        shelf.airDropAll(from: nil)
                    }
                    OtterActionLink(title: "Vider", icon: "trash", tint: Otter.textTertiary) {
                        shelf.clear()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            shelf.handleDrop(providers)
        }
    }


    private func itemRow(_ url: URL) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(url.lastPathComponent)
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button { shelf.remove(url) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Otter.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Otter.tileFill))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Retirer de l'étagère")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: Otter.Radius.medium, style: .continuous)
                .fill(hovered == url ? Otter.tileFillActive : .clear)
        )
        .onHover { hovering in
            if hovering { hovered = url } else if hovered == url { hovered = nil }
        }
        .animation(Otter.hoverMotion, value: hovered)
        // Permet de re-glisser le fichier depuis l'étagère vers ailleurs.
        .onDrag { NSItemProvider(object: url as NSURL) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var found = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            found = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in shelf.add([url]) }
            }
        }
        return found
    }
}
