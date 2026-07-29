import SwiftUI

/// Forme de l'encoche : un "nub" du haut qui ne dépasse JAMAIS la largeur réelle
/// de l'encoche physique (`topWidth`), pour ne jamais recouvrir la vraie barre
/// de menus qui la flanque. La forme ne s'évase vers `rect.width` qu'à partir
/// de `topHeight` (hauteur de l'encoche/barre de menus).
///
/// L'évasement est en « goutte d'eau » : les flancs du nub se déversent sur les
/// épaules par un congé tangent (courbe concave, comme les coins bas de la vraie
/// encoche), et les coins externes des épaules sont arrondis vers le bas. Comme
/// la largeur des épaules part de zéro pendant l'animation de frame, la forme
/// morphe continûment du nub seul vers la carte complète — l'effet liquide vient
/// de là, pas d'un paramètre discret.
struct NotchShape: Shape {
    var topWidth: CGFloat?
    var topHeight: CGFloat = 0
    var bottomRadius: CGFloat = 12

    /// Rayon du congé nub→épaule et des coins externes des épaules.
    /// 12 validé visuellement (rendu raster du path) : assez pour l'effet
    /// « déversement », pas assez pour manger les épaules.
    var flareRadius: CGFloat = 12

    /// Anime le rayon bas (10 replié → 24 déplié) pendant le morphing, au lieu
    /// d'un saut discret au changement d'état.
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let nubWidth = min(topWidth ?? rect.width, rect.width)
        let nubHeight = min(max(topHeight, 0), rect.height)
        let r = min(bottomRadius, min(rect.width, rect.height - nubHeight) / 2)

        var path = Path()

        // Largeur d'une épaule (de chaque côté du nub).
        let shoulder = (rect.width - nubWidth) / 2

        guard shoulder > 0.5, nubHeight > 0 else {
            // Pas d'évasement à faire (repliée, ou pas d'encoche réelle) :
            // simple rectangle à coins bas arrondis, comme avant.
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + r, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
            return path
        }

        let nubMinX = rect.midX - nubWidth / 2
        let nubMaxX = rect.midX + nubWidth / 2
        let flareY = rect.minY + nubHeight

        // Congé (j) et coin externe (t), bornés pour que les courbes ne se
        // chevauchent jamais pendant l'animation (épaules naissantes).
        let j = min(flareRadius, nubHeight, shoulder / 2)
        let t = min(flareRadius, shoulder / 2, rect.height - nubHeight)

        path.move(to: CGPoint(x: nubMinX, y: rect.minY))
        // Flanc gauche du nub, qui se déverse sur l'épaule (congé tangent).
        path.addLine(to: CGPoint(x: nubMinX, y: flareY - j))
        path.addQuadCurve(
            to: CGPoint(x: nubMinX - j, y: flareY),
            control: CGPoint(x: nubMinX, y: flareY)
        )
        // Épaule gauche, puis coin externe arrondi vers le bas.
        path.addLine(to: CGPoint(x: rect.minX + t, y: flareY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: flareY + t),
            control: CGPoint(x: rect.minX, y: flareY)
        )
        // Flanc gauche et coins bas.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Flanc droit, coin externe, épaule droite, congé vers le nub.
        path.addLine(to: CGPoint(x: rect.maxX, y: flareY + t))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - t, y: flareY),
            control: CGPoint(x: rect.maxX, y: flareY)
        )
        path.addLine(to: CGPoint(x: nubMaxX + j, y: flareY))
        path.addQuadCurve(
            to: CGPoint(x: nubMaxX, y: flareY - j),
            control: CGPoint(x: nubMaxX, y: flareY)
        )
        path.addLine(to: CGPoint(x: nubMaxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
