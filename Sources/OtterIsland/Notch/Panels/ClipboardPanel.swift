import SwiftUI
import AppKit

/// Panneau Presse-papier : historique récent, clic pour coller dans l'app active.
struct ClipboardPanel: View {
    @ObservedObject var clipboard: ClipboardManager
    let onPick: (ClipboardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if clipboard.items.isEmpty {
                Text("Presse-papier vide")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.6))
                Text("Copie quelque chose, ça apparaîtra ici.")
                    .font(.caption)
                    .foregroundStyle(.black.opacity(0.4))
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
                .foregroundStyle(.black.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func itemRow(_ item: ClipboardItem) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(spacing: 6) {
                if let data = item.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text("Image")
                        .font(.caption2)
                        .foregroundStyle(.black)
                } else if let text = item.text {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 8))
                        .foregroundStyle(.black.opacity(0.5))
                    Text(text.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption2)
                        .foregroundStyle(.black)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
