import SwiftUI
import AppKit

/// Panneau Captures : historique des captures d'écran, ouverture/suppression.
struct ScreenshotsPanel: View {
    @ObservedObject var screenshot: ScreenshotWatcher

    private let columns = [GridItem(.adaptive(minimum: 46, maximum: 46), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if screenshot.history.isEmpty {
                emptyHint
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(screenshot.history, id: \.self) { url in
                            thumbnail(url)
                        }
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    Button { screenshot.clearHistory() } label: {
                        Text("Vider").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.4))
            Text("Tes captures d'écran s'affichent ici")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func thumbnail(_ url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            ZStack(alignment: .topTrailing) {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(.white.opacity(0.15), lineWidth: 0.5)
                        )
                }
                Button {
                    screenshot.remove(url)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white, .black.opacity(0.5))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .buttonStyle(.plain)
        .help(url.lastPathComponent)
        // Glisser la miniature directement où on veut (chat, mail, Finder…).
        .onDrag { NSItemProvider(object: url as NSURL) }
    }
}
