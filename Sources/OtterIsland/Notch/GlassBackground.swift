import SwiftUI

extension View {
    /// Fond "verre" pour les petites cartes de l'encoche (HUD, aperçus, boutons).
    /// Liquid Glass natif sur macOS 26+, matériau translucide + voile teinté
    /// avant ça (le projet cible macOS 14+).
    @ViewBuilder
    func liquidGlassBackground<S: Shape>(in shape: S, tint: Color = .black.opacity(0.55)) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint))
        }
    }
}
