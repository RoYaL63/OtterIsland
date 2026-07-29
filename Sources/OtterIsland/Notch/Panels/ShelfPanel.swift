import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Panneau Étagère : zone de dépôt de fichiers, envoi AirDrop, glisser vers ailleurs.
struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if shelf.items.isEmpty {
                dropHint
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(shelf.items, id: \.self) { url in
                            itemRow(url)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        shelf.airDropAll(from: nil)
                    } label: {
                        Label("AirDrop", systemImage: "shareplay")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)

                    Button { shelf.clear() } label: {
                        Text("Vider").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            shelf.handleDrop(providers)
        }
    }

    private var dropHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.75))
            Text("Dépose des fichiers ici")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemRow(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(url.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button { shelf.remove(url) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
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
