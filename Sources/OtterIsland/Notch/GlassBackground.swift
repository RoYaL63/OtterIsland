import SwiftUI

extension View {
    /// Fond "verre" pour les petites cartes de l'encoche (HUD, aperçus, boutons).
    /// Liquid Glass natif sur macOS 26+, matériau translucide + voile teinté
    /// avant ça (le projet cible macOS 14+).
    @ViewBuilder
    // Teinte par défaut foncée façon tuile du Centre de contrôle : les cartes
    // (HUD, aperçu capture) doivent porter du texte blanc bien lisible.
    func liquidGlassBackground<S: Shape>(in shape: S, tint: Color = .black.opacity(0.7)) -> some View {
        if #available(macOS 26.0, *) {
            // .interactive() donne les reflets/animations fluides du vrai Liquid
            // Glass (effet "goutte d'eau" au survol/clic), tout en gardant une
            // teinte sombre opaque pour le contraste.
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint))
        }
    }
}
