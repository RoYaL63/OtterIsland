import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Panneau Étagère : zone de dépôt de fichiers, envoi AirDrop, glisser vers ailleurs.
struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shelf.items.isEmpty {
                OtterEmptyState(
                    icon: "arrow.down.doc",
                    title: "Dépose des fichiers ici",
                    subtitle: "Ou glisse-les sur l'encoche repliée."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(shelf.items, id: \.self) { url in
                            itemRow(url)
                        }
                    }
                }
                OtterDivider(axis: .horizontal)
                HStack(spacing: 12) {
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
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(url.lastPathComponent)
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button { shelf.remove(url) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Otter.textTertiary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Retirer de l'étagère")
        }
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
