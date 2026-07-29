import SwiftUI

extension View {
    /// Fond "verre" pour les surfaces FLOTTANTES de premier niveau (île, HUD,
    /// aperçu capture) — la « couche fonctionnelle » au sens de la doc Apple
    /// « Adopting Liquid Glass ». Liquid Glass natif sur macOS 26+, matériau
    /// translucide + voile teinté avant ça (le projet cible macOS 14+).
    ///
    /// NE PAS utiliser pour un élément posé À L'INTÉRIEUR d'une surface déjà
    /// en verre (pastille d'onglet, bouton, chip) : Apple déconseille
    /// explicitement d'empiler du verre sur du verre — c'est ce qui rendait
    /// les pastilles gris pâle illisibles. Utiliser `chipBackground` à la place.
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

    /// Fond de pastille/chip/bouton À L'INTÉRIEUR de l'île : remplissage plein
    /// + liseré fin, aucun effet verre (voir liquidGlassBackground ci-dessus).
    /// Le contraste est garanti quel que soit ce qui passe derrière l'encoche.
    func chipBackground<S: Shape>(in shape: S, tint: Color) -> some View {
        background(
            shape.fill(tint)
                .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 0.5))
        )
    }
}
