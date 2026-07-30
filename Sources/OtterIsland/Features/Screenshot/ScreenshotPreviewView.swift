import SwiftUI

/// Carte transitoire affichée sous l'encoche quand une capture d'écran vient
/// d'être prise. Clic pour l'ouvrir, croix pour l'écarter, glisser pour la
/// déposer ailleurs.
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

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(nsImage: shot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Otter.Radius.small, style: .continuous)
                                .stroke(Otter.accent.opacity(0.8), lineWidth: 1)
                        )
                        // Glisser directement la capture n'importe où (chat, mail,
                        // Finder…) sans passer par l'onglet Captures.
                        .onDrag { NSItemProvider(object: shot.url as NSURL) }

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
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Otter.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Écarter")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(width: 230, height: 46)
        .liquidGlassBackground(
            in: RoundedRectangle(cornerRadius: Otter.Radius.large + 4, style: .continuous),
            tint: .black.opacity(0.78)
        )
    }
}
