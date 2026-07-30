import SwiftUI

/// Le vocabulaire visuel de l'encoche, en un seul endroit.
///
/// Avant, chaque vue improvisait : 14 opacités de blanc différentes, 28 tailles
/// de police écrites à la main, et l'orange qui servait à la fois d'accent de
/// marque ET de couleur d'alerte — impossible de distinguer « clique ici » de
/// « attention ». Tout passe désormais par ces jetons.
///
/// Règle de couleur : `accent` pour ce qui est vivant/interactif, `warning` et
/// `danger` UNIQUEMENT quand quelque chose ne va pas. Si tout est orange, plus
/// rien n'alerte.
enum Otter {

    // MARK: Couleurs

    /// Aqua de l'icône (#5EE9D3) : la couleur de marque. Sélection, liens,
    /// actions. Choisie sur l'illustration elle-même — l'app et son icône
    /// doivent avoir l'air d'être du même monde.
    static let accent = Color(red: 0.369, green: 0.914, blue: 0.827)
    /// Cyan de l'icône (#3BCAE8), pour les dégradés d'accent.
    static let accentDeep = Color(red: 0.231, green: 0.792, blue: 0.910)

    /// Quelque chose demande une action de l'utilisateur (permission manquante,
    /// demande Claude Code en attente).
    static let warning = Color.orange
    /// Quelque chose va mal (batterie critique, RAM saturée, clavier bloqué).
    static let danger = Color.red
    /// Tout va bien (en charge).
    static let positive = Color(red: 0.42, green: 0.92, blue: 0.62)

    // MARK: Texte — trois niveaux, pas un de plus

    /// Titres, valeurs, tout ce qui se lit vraiment.
    static let textPrimary = Color.white
    /// Libellés, heures, unités : présents mais en retrait.
    static let textSecondary = Color.white.opacity(0.62)
    /// Aides, états vides, contenu absent.
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: Surfaces internes à l'île

    /// Filet de séparation. Une seule valeur, partout.
    static let separator = Color.white.opacity(0.13)
    /// Remplissage des pastilles et boutons posés sur le verre.
    static let chipFill = Color.white.opacity(0.10)
    /// Liseré des mêmes pastilles.
    static let chipStroke = Color.white.opacity(0.14)

    // MARK: Géométrie

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 9
        static let large: CGFloat = 14
    }

    /// Colonne d'alignement des icônes de rangée : toutes les glyphes SF Symbol
    /// d'une liste tombent sur la même verticale, quelle que soit leur largeur.
    static let iconColumn: CGFloat = 13
}

// MARK: - Échelle typographique

extension Font {
    /// Titre d'un bloc ou d'une carte.
    static let otterTitle = Font.system(size: 12, weight: .semibold)
    /// Corps d'une rangée : titre d'évènement, nom de morceau, nom de fichier.
    static let otterBody = Font.system(size: 11, weight: .medium)
    /// Libellé d'un indicateur (« RAM », « Pomodoro »).
    static let otterLabel = Font.system(size: 10.5, weight: .regular)
    /// Valeur chiffrée. Chiffres à chasse fixe : le pourcentage de RAM ne doit
    /// pas faire danser la colonne à chaque relevé.
    static let otterValue = Font.system(size: 10.5, weight: .semibold).monospacedDigit()
    /// Méta discrète : heure d'un RDV, durée restante.
    static let otterMeta = Font.system(size: 10, weight: .regular)
    /// Micro-libellé : initiales des jours, minuterie.
    static let otterMicro = Font.system(size: 8.5, weight: .semibold)
}

// MARK: - Composants partagés

/// Filet de séparation. Existait en trois exemplaires copiés-collés, à des
/// opacités différentes.
struct OtterDivider: View {
    var axis: Axis = .vertical

    var body: some View {
        Rectangle()
            .fill(Otter.separator)
            .frame(
                width: axis == .vertical ? 1 : nil,
                height: axis == .vertical ? nil : 1
            )
    }
}

/// État vide d'un panneau. Chaque panneau avait le sien, avec une icône d'une
/// taille différente et un texte d'une opacité différente.
struct OtterEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(Otter.textTertiary)
            Text(title)
                .font(.otterBody)
                .foregroundStyle(Otter.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(.otterMeta)
                    .foregroundStyle(Otter.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Rangée d'indicateur : icône alignée, libellé, valeur à droite. RAM, batterie,
/// Pomodoro et prochain RDV étaient quatre variations manuscrites de la même
/// chose, chacune avec ses propres tailles.
struct OtterStatRow<Trailing: View>: View {
    let icon: String
    let iconTint: Color
    let label: String
    /// Jauge fine sous la rangée, 0…1. Un pourcentage se lit, un niveau se
    /// perçoit : la barre dit « ça monte » avant qu'on ait lu le chiffre, et
    /// elle donne du corps à une colonne qui était très vide.
    var progress: Double?
    /// Couleur de la jauge. Séparée de `iconTint` : à l'état normal, le chiffre
    /// est blanc (lisibilité) mais une barre blanche pleine largeur écrase toute
    /// la carte — la jauge, elle, reste en aqua discret.
    var progressTint: Color = Otter.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(iconTint)
                    .frame(width: Otter.iconColumn)
                Text(label)
                    .font(.otterLabel)
                    .foregroundStyle(Otter.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing
            }
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(progressTint.opacity(0.75))
                            .frame(width: max(2, geo.size.width * min(1, max(0, progress))))
                    }
                }
                .frame(height: 2.5)
                .padding(.leading, Otter.iconColumn + 7)
            }
        }
    }
}

/// Petit bouton rond posé sur le verre (nettoyage, miroir…).
struct OtterIconButton: View {
    let icon: String
    var tint: Color = Otter.textPrimary
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(isHovering ? Color.white.opacity(0.18) : Otter.chipFill)
                .overlay(Circle().stroke(Otter.chipStroke, lineWidth: 0.5))
        )
        // Un retour au survol : sans lui, rien ne dit que ces pastilles sont
        // cliquables tant qu'on n'a pas cliqué.
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(help)
    }
}

/// Lien d'action textuel discret (« Vider », « AirDrop », « Autoriser »).
struct OtterActionLink: View {
    let title: String
    var icon: String?
    var tint: Color = Otter.textSecondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                }
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isHovering ? Otter.textPrimary : tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
