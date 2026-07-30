import SwiftUI
import AppKit
import ImageIO

/// Vignette d'un fichier image, décodée À LA TAILLE D'AFFICHAGE et mise en cache.
///
/// Avant : `NSImage(contentsOf:)` décodait la capture en pleine résolution — une
/// capture Retina 5K pèse ~30 Mo une fois décompressée — pour l'afficher dans
/// 46 pt, et le panneau Captures le refaisait à CHAQUE passe de rendu, pour
/// chaque miniature. `CGImageSource` sait produire directement la vignette sans
/// décoder l'image entière.
struct FileThumbnail: View {
    let url: URL
    var size: CGSize
    var cornerRadius: CGFloat = 4

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: min(size.height * 0.5, 14)))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 0.5)
        )
        .task(id: url) {
            // ×2 pour rester net sur écran Retina.
            image = await ThumbnailCache.shared.thumbnail(
                for: url,
                maxPixel: Int(max(size.width, size.height) * 2)
            )
        }
    }
}

/// Cache mémoire des vignettes, vidé par le système sous pression mémoire.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 120
    }

    func thumbnail(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = "\(url.path)|\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        // Décodage hors du main thread : ouvrir 40 captures d'un coup ferait
        // sinon sauter l'animation d'ouverture de l'encoche.
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decode(url: url, maxPixel: maxPixel)
        }.value
        guard let decoded else { return nil }

        let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        cache.setObject(image, forKey: key)
        return image
    }

    private nonisolated static func decode(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
