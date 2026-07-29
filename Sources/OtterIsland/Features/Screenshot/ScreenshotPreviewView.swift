import SwiftUI

/// Carte transitoire affichée sous l'encoche quand une capture d'écran vient
/// d'être prise. Clic pour l'ouvrir, croix pour l'écarter.
struct ScreenshotPreviewView: View {
    let shot: ScreenshotWatcher.Shot
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(nsImage: shot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(.white.opacity(0.25), lineWidth: 0.5)
                        )
                    Text("Capture d'écran")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(width: 220, height: 42)
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
