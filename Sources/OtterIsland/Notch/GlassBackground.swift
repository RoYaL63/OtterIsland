import SwiftUI

// MARK: - Liseré spéculaire

/// Le liseré lumineux qui court sur la tranche d'une surface en verre : la
/// lumière frappe le haut, glisse sur les flancs, s'éteint au creux, puis
/// revient un peu en bas (le verre réfracte ce qui passe dessous).
///
/// C'est ce liseré — pas la transparence — qui fait lire une surface comme du
/// verre ÉPAIS plutôt que comme un rectangle gris translucide. Apple l'utilise
/// sur chaque tuile du Centre de contrôle ; sans lui, une teinte translucide
/// reste un aplat.
struct SpecularRim<S: Shape>: View {
    let shape: S
    /// 0 = éteint, 1 = pleine lumière. Sert à faire respirer le liseré selon
    /// l'état (île repliée, tuile au repos…).
    var strength: Double = 1
    var lineWidth: CGFloat = 1

    var body: some View {
        shape
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.46 * strength), location: 0.00),
                        .init(color: .white.opacity(0.16 * strength), location: 0.26),
                        .init(color: .white.opacity(0.03 * strength), location: 0.60),
                        .init(color: .white.opacity(0.18 * strength), location: 1.00),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: lineWidth
            )
            .allowsHitTesting(false)
    }
}

extension View {

    // MARK: Couche flottante (verre véritable)

    /// Matériau verre NU pour les surfaces FLOTTANTES de premier niveau (île,
    /// HUD, aperçu capture) — la « couche fonctionnelle » au sens de la doc
    /// Apple « Adopting Liquid Glass ». Liquid Glass natif sur macOS 26+,
    /// matériau translucide + voile teinté avant ça (le projet cible macOS 14+).
    ///
    /// Nu = sans liseré ni ombre : l'appelant compose les siens (l'encoche a
    /// besoin d'un liseré qui s'allume au dépliage). Pour une carte ordinaire,
    /// préférer `liquidGlassCard`, qui ajoute la tranche et l'ombre portée.
    ///
    /// NE PAS utiliser pour un élément posé À L'INTÉRIEUR d'une surface déjà en
    /// verre (tuile, pastille, bouton) : Apple déconseille explicitement
    /// d'empiler du verre sur du verre. Utiliser `glassTile` / `chipBackground`.
    @ViewBuilder
    func liquidGlassBackground<S: Shape>(in shape: S, tint: Color = Otter.glassTint) -> some View {
        if #available(macOS 26.0, *) {
            // .interactive() donne les reflets et le rebond « goutte d'eau » du
            // vrai Liquid Glass au survol et au clic.
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint))
        }
    }

    /// Carte en verre complète : matériau + tranche lumineuse + ombre portée.
    /// C'est la forme standard d'une surface flottante (HUD, aperçu capture).
    func liquidGlassCard<S: Shape>(
        in shape: S,
        tint: Color = Otter.glassTint,
        shadow: Double = 0.34
    ) -> some View {
        liquidGlassBackground(in: shape, tint: tint)
            .overlay(SpecularRim(shape: shape))
            .shadow(color: .black.opacity(shadow), radius: 14, y: 7)
    }

    // MARK: Couche interne (modules posés SUR le verre)

    /// Tuile groupée à l'intérieur d'une surface en verre — l'équivalent d'un
    /// module du Centre de contrôle. Remplissage translucide + tranche discrète,
    /// jamais de second matériau verre (verre sur verre = bouillie grise).
    ///
    /// Le groupement REMPLACE les filets de séparation : c'est l'écart entre
    /// deux tuiles qui dit « ceci est un autre sujet », pas un trait.
    func glassTile<S: Shape>(
        in shape: S,
        fill: Color = Otter.tileFill,
        rim: Double = 0.55
    ) -> some View {
        background(shape.fill(fill))
            .overlay(SpecularRim(shape: shape, strength: rim, lineWidth: 0.75))
    }

    /// Fond de pastille/chip/bouton à l'intérieur de l'île : remplissage plein
    /// + tranche fine. Le contraste est garanti quel que soit ce qui passe
    /// derrière l'encoche.
    func chipBackground<S: Shape>(in shape: S, tint: Color) -> some View {
        background(shape.fill(tint))
            .overlay(SpecularRim(shape: shape, strength: 0.7, lineWidth: 0.75))
    }
}
