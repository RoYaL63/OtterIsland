import SwiftUI

/// Texte sur une ligne qui défile doucement quand il est trop long, au lieu
/// d'être coupé par « … ». Aller-retour avec une pause à chaque bout (plutôt
/// qu'une boucle sans fin) : on lit le début du titre la plupart du temps, ce
/// qui est l'info utile. Les bords s'estompent pendant le défilement pour que
/// le texte ne semble pas heurter les boutons voisins.
///
/// Si le texte tient dans la place disponible, rien ne bouge et aucune
/// minuterie ne tourne.
struct MarqueeText: View {
    let text: String
    var font: Font = .caption2
    /// Vitesse de défilement, en points par seconde.
    var speed: Double = 22
    /// Temps d'arrêt à chaque extrémité, en secondes.
    var pause: Double = 1.8

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    /// Largeur du dégradé d'estompage sur chaque bord.
    private let fade: CGFloat = 12

    /// Nombre de points qui dépassent : 0 = le texte tient, pas d'animation.
    private var overflow: CGFloat {
        guard textWidth > 0, containerWidth > 0 else { return 0 }
        return max(0, textWidth - containerWidth)
    }

    var body: some View {
        Group {
            if overflow > 0.5 {
                // 30 img/s : assez fluide pour un défilement lent, deux fois
                // moins de réveils que le rafraîchissement écran.
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    let offset = scrollOffset(at: context.date)
                    label
                        .offset(x: -offset)
                        // minWidth 0 : sans ça le `fixedSize` du texte remonte
                        // comme largeur minimale et c'est la RANGÉE qui déborde
                        // (le titre passait sous les boutons de lecture au lieu
                        // d'être borné puis de défiler).
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        .mask(edgeFade(offset: offset))
                }
            } else {
                label
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: MarqueeWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(MarqueeWidthKey.self) { width in
            // `onPreferenceChange` passe une fermeture @Sendable : on repasse
            // explicitement sur le main actor pour toucher l'état SwiftUI.
            Task { @MainActor in containerWidth = width }
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MarqueeTextWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(MarqueeTextWidthKey.self) { width in
                Task { @MainActor in textWidth = width }
            }
    }

    /// Position du texte à l'instant `date`, en aller-retour :
    /// pause → défile vers la gauche → pause → revient.
    private func scrollOffset(at date: Date) -> CGFloat {
        let travel = Double(overflow) / speed
        let cycle = 2 * (pause + travel)
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)

        if phase < pause {
            return 0
        } else if phase < pause + travel {
            return CGFloat((phase - pause) * speed)
        } else if phase < 2 * pause + travel {
            return overflow
        } else {
            return overflow - CGFloat((phase - 2 * pause - travel) * speed)
        }
    }

    /// Estompe le bord gauche dès qu'on a commencé à défiler, le bord droit tant
    /// qu'il reste du texte à venir. À l'arrêt en début de titre, la première
    /// lettre reste donc parfaitement nette.
    private func edgeFade(offset: CGFloat) -> some View {
        let leading = min(1, max(0, offset / fade))
        let trailing = min(1, max(0, (overflow - offset) / fade))
        let f = containerWidth > 0 ? min(0.4, fade / containerWidth) : 0
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(1 - leading), location: 0),
                .init(color: .white, location: f),
                .init(color: .white, location: 1 - f),
                .init(color: .white.opacity(1 - trailing), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
