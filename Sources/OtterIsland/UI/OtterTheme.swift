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
///
/// Règle de matière (doc Apple « Adopting Liquid Glass ») : UNE seule couche de
/// verre, celle de l'île. Tout ce qui est posé dessus — tuiles, pastilles,
/// boutons — est un remplissage translucide avec une tranche lumineuse, jamais
/// un second matériau verre.
enum Otter {

    // MARK: Couleurs

    /// Aqua de l'icône (#5EE9D3) : la couleur de marque. Sélection, liens,
    /// actions. Choisie sur l'illustration elle-même — l'app et son icône
    /// doivent avoir l'air d'être du même monde.
    static let accent = Color(red: 0.369, green: 0.914, blue: 0.827)
    /// Cyan de l'icône (#3BCAE8), pour les dégradés d'accent.
    static let accentDeep = Color(red: 0.231, green: 0.792, blue: 0.910)

    /// Dégradé de marque. Un aplat de couleur reste plat ; un dégradé attrape la
    /// lumière comme le fait un contrôle actif du système.
    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .top,
        endPoint: .bottom
    )

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
    static let textSecondary = Color.white.opacity(0.64)
    /// Aides, états vides, contenu absent.
    static let textTertiary = Color.white.opacity(0.40)

    // MARK: Matière

    /// Teinte du verre de premier niveau. Assez sombre pour poser un plancher de
    /// contraste sous le texte blanc, assez claire pour que le fond d'écran
    /// continue de vivre à travers — c'est tout l'intérêt du matériau.
    static let glassTint = Color.black.opacity(0.60)

    /// Remplissage d'une tuile posée sur le verre (module du Centre de contrôle).
    static let tileFill = Color.white.opacity(0.07)
    /// La même, survolée ou active.
    static let tileFillActive = Color.white.opacity(0.13)

    /// Filet de séparation. À n'utiliser que DANS une tuile ; entre deux sujets,
    /// c'est l'écart entre les tuiles qui sépare, pas un trait.
    static let separator = Color.white.opacity(0.12)
    /// Remplissage des pastilles et boutons posés sur le verre.
    static let chipFill = Color.white.opacity(0.11)
    /// Liseré des mêmes pastilles.
    static let chipStroke = Color.white.opacity(0.16)

    // MARK: Géométrie

    /// Rayons concentriques : une pastille dans une tuile dans une carte doit
    /// voir ses rayons décroître régulièrement, sinon les coins « pincent ».
    enum Radius {
        static let xsmall: CGFloat = 6
        static let small: CGFloat = 9
        static let medium: CGFloat = 13
        static let large: CGFloat = 18
        static let xlarge: CGFloat = 26
    }

    /// Colonne d'alignement des icônes de rangée : toutes les glyphes d'une
    /// liste tombent sur la même verticale, quelle que soit leur largeur.
    /// Dimensionnée pour la pastille ronde d'`OtterIconBadge`.
    static let iconColumn: CGFloat = 19

    // MARK: Mouvement

    /// Réaction au survol : rapide, sans rebond. Le verre suit le curseur, il
    /// ne le rattrape pas.
    static let hoverMotion: Animation = .smooth(duration: 0.18)
    /// Réaction à un changement d'état (onglet, sélection) : léger dépassement,
    /// comme les contrôles du système.
    static let selectionMotion: Animation = .spring(response: 0.34, dampingFraction: 0.76)
}

// MARK: - Échelle typographique

extension Font {
    /// Titre d'un bloc ou d'une carte.
    static let otterTitle = Font.system(size: 12.5, weight: .semibold)
    /// Corps d'une rangée : titre d'évènement, nom de morceau, nom de fichier.
    static let otterBody = Font.system(size: 11.5, weight: .medium)
    /// Libellé d'un indicateur (« RAM », « Pomodoro »).
    static let otterLabel = Font.system(size: 11, weight: .regular)
    /// Valeur chiffrée. Chiffres à chasse fixe : le pourcentage de RAM ne doit
    /// pas faire danser la colonne à chaque relevé.
    static let otterValue = Font.system(size: 11, weight: .semibold).monospacedDigit()
    /// Méta discrète : heure d'un RDV, durée restante.
    static let otterMeta = Font.system(size: 10, weight: .regular)
    /// Micro-libellé : initiales des jours, minuterie.
    static let otterMicro = Font.system(size: 8.5, weight: .semibold)
}

// MARK: - Tuile

/// Module groupé façon Centre de contrôle : un contenu, un fond translucide,
/// une tranche lumineuse, un grand rayon.
///
/// Remplace les filets de séparation entre sujets : l'œil lit « bloc » avant
/// d'avoir lu quoi que ce soit, et chaque groupe peut respirer sans que la
/// carte parte en lignes horizontales.
struct OtterTile<Content: View>: View {
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 8
    var radius: CGFloat = Otter.Radius.large
    var fill: Color = Otter.tileFill
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .glassTile(in: RoundedRectangle(cornerRadius: radius, style: .continuous), fill: fill)
    }
}

// MARK: - Composants partagés

/// Filet de séparation, réservé à l'intérieur d'une tuile — plus aucun panneau
/// ne s'en sert depuis le passage aux modules groupés, mais il reste le seul
/// filet légitime du système visuel : à réutiliser tel quel plutôt que de
/// réinventer un `Rectangle` à une opacité de plus.
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

/// Pastille ronde d'icône, comme celles qui ouvrent chaque module du Centre de
/// contrôle : la couleur vit dans la pastille, pas dans le texte — le libellé
/// reste blanc et lisible, et l'état se lit d'un coup d'œil sur la rondelle.
struct OtterIconBadge: View {
    let icon: String
    var tint: Color = Otter.textPrimary
    var size: CGFloat = Otter.iconColumn
    /// Pastille pleine en couleur (état actif) plutôt que teintée translucide.
    var isFilled: Bool = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(isFilled ? Color.black.opacity(0.82) : tint)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(tint.opacity(isFilled ? 1 : 0.16))
                    .overlay(Circle().stroke(.white.opacity(isFilled ? 0.28 : 0.10), lineWidth: 0.5))
            )
    }
}

/// Jauge capsule. Épaisseur du Centre de contrôle (un filet de 2 pt ne se
/// perçoit pas ; à 4 pt le niveau se lit avant le chiffre).
struct OtterMeter: View {
    let value: Double
    var tint: Color = Otter.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.62)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

/// État vide d'un panneau. Chaque panneau avait le sien, avec une icône d'une
/// taille différente et un texte d'une opacité différente.
struct OtterEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Otter.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Otter.tileFill)
                        .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 0.75))
                )
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

/// Rangée d'indicateur : pastille d'icône, libellé, valeur à droite, jauge
/// optionnelle. RAM, batterie, Pomodoro et prochain RDV étaient quatre
/// variations manuscrites de la même chose, chacune avec ses propres tailles.
struct OtterStatRow<Trailing: View>: View {
    let icon: String
    let iconTint: Color
    let label: String
    /// Jauge fine sous la rangée, 0…1. Un pourcentage se lit, un niveau se
    /// perçoit : la barre dit « ça monte » avant qu'on ait lu le chiffre.
    var progress: Double?
    /// Couleur de la jauge. Séparée de `iconTint` : à l'état normal, le chiffre
    /// est blanc (lisibilité) mais une barre blanche pleine largeur écrase toute
    /// la carte — la jauge, elle, reste en aqua discret.
    var progressTint: Color = Otter.accent
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                OtterIconBadge(icon: icon, tint: iconTint)
                Text(label)
                    .font(.otterLabel)
                    .foregroundStyle(Otter.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing
            }
            if let progress {
                OtterMeter(value: progress, tint: progressTint)
                    .padding(.leading, Otter.iconColumn + 8)
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
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(tint)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(isHovering ? Otter.tileFillActive : Otter.chipFill)
                .overlay(SpecularRim(shape: Circle(), strength: isHovering ? 1 : 0.7, lineWidth: 0.75))
        )
        // Le verre s'enfonce sous le doigt puis rebondit : sans ce retour, une
        // pastille ne se distingue pas d'une décoration.
        .scaleEffect(isPressed ? 0.92 : 1)
        .onHover { isHovering = $0 }
        .animation(Otter.hoverMotion, value: isHovering)
        .animation(Otter.selectionMotion, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .help(help)
    }
}

/// Lien d'action discret (« Vider », « AirDrop », « Autoriser »). Dessiné comme
/// une pastille du système : le survol l'allume au lieu de ne changer que la
/// couleur du texte — on voit la cible avant de cliquer.
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
            // 6 pt et pas 8 : trois de ces pastilles doivent tenir côte à côte
            // dans la colonne d'actions de l'onglet Captures, sinon les libellés
            // se font tronquer en « C… », « O… », « R… ».
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(isHovering ? Otter.tileFillActive : Otter.tileFill)
                    .overlay(SpecularRim(shape: Capsule(), strength: isHovering ? 0.9 : 0.45, lineWidth: 0.75))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Otter.hoverMotion, value: isHovering)
    }
}

/// Bouton pleine largeur des cartes (Approuver / Refuser, Déverrouiller).
/// `prominent` = action principale en aqua, sinon pastille de verre neutre.
struct OtterPillButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tint: Color = Otter.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundStyle(prominent ? Color.black.opacity(0.84) : Otter.textPrimary)
            .background(
                ZStack {
                    if prominent {
                        Capsule().fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.78)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    } else {
                        Capsule().fill(Otter.chipFill)
                    }
                    SpecularRim(shape: Capsule(), strength: prominent ? 0.9 : 0.7, lineWidth: 0.75)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Otter.hoverMotion, value: configuration.isPressed)
    }
}
