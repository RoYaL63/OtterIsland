import SwiftUI

/// Notification transitoire affichée en bas à droite de l'écran quand une
/// capture d'écran vient d'être prise — au même endroit que la vignette
/// flottante de macOS, là où l'œil la cherche déjà.
///
/// Toute la carte est cliquable : un clic ouvre la capture dans l'éditeur
/// (Aperçu, avec ses outils d'annotation). La croix, visible au survol, l'écarte ;
/// glisser la carte dépose le fichier ailleurs (chat, mail, Finder…).
///
/// Le sous-titre « Copiée — ⌘V » n'est pas décoratif : la capture part vraiment
/// dans le presse-papier système (voir `NotchViewModel.showScreenshot`), et sans
/// le dire, personne ne pense à essayer.
struct ScreenshotPreviewView: View {
    let shot: ScreenshotWatcher.Shot
    /// false si la copie automatique est désactivée dans les réglages.
    var didCopy: Bool = true
    var onOpen: () -> Void
    var onDismiss: () -> Void
    /// Survol de la carte : suspend l'effacement automatique tant que le
    /// pointeur est dessus.
    var onHover: (Bool) -> Void = { _ in }

    static let size = CGSize(width: 260, height: 196)

    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: shot.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 5, y: 2)

            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Capture d'écran")
                        .font(.otterBody)
                        .foregroundStyle(Otter.textPrimary)
                    if didCopy {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                            Text("Copiée — ⌘V")
                                .font(.otterMicro)
                        }
                        .foregroundStyle(Otter.accent)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Modifier")
                        .font(.otterMeta)
                }
                .foregroundStyle(isHovering ? Otter.accent : Otter.textSecondary)
            }
        }
        .padding(10)
        .frame(width: Self.size.width, height: Self.size.height)
        .liquidGlassCard(in: shape)
        .overlay(
            shape.stroke(Otter.accent.opacity(isHovering ? 0.85 : 0), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            // Croix en haut à gauche, comme les notifications système : visible
            // au survol seulement, pour ne pas encombrer l'aperçu.
            if isHovering {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Otter.textPrimary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.black.opacity(0.7)))
                        .overlay(Circle().stroke(Otter.chipStroke, lineWidth: 0.75))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Écarter")
                .offset(x: -6, y: -6)
                .transition(.opacity)
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1)
        .contentShape(shape)
        .onTapGesture(perform: onOpen)
        // Glisser directement la capture n'importe où sans passer par
        // l'onglet Captures.
        .onDrag { NSItemProvider(object: shot.url as NSURL) }
        .onHover { hovering in
            withAnimation(Otter.hoverMotion) { isHovering = hovering }
            onHover(hovering)
        }
        .help("Cliquer pour ouvrir dans l'éditeur")
    }
}
