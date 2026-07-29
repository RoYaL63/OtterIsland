import SwiftUI

/// Forme de l'encoche : un "nub" du haut qui ne dépasse JAMAIS la largeur réelle
/// de l'encoche physique (`topWidth`), pour ne jamais recouvrir la vraie barre
/// de menus qui la flanque. La forme ne s'évase vers `rect.width` qu'à partir
/// de `topHeight` (hauteur de l'encoche/barre de menus), avec des coins bas
/// arrondis. Sans `topWidth` (Mac sans encoche réelle), le nub prend toute la
/// largeur du rect, comme avant.
struct NotchShape: Shape {
    var topWidth: CGFloat?
    var topHeight: CGFloat = 0
    var bottomRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let nubWidth = min(topWidth ?? rect.width, rect.width)
        let nubHeight = min(max(topHeight, 0), rect.height)
        let r = min(bottomRadius, min(rect.width, rect.height - nubHeight) / 2)

        var path = Path()

        guard nubWidth < rect.width - 0.5, nubHeight > 0 else {
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

        path.move(to: CGPoint(x: nubMinX, y: rect.minY))
        path.addLine(to: CGPoint(x: nubMinX, y: flareY))
        path.addLine(to: CGPoint(x: rect.minX, y: flareY))
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
        path.addLine(to: CGPoint(x: rect.maxX, y: flareY))
        path.addLine(to: CGPoint(x: nubMaxX, y: flareY))
        path.addLine(to: CGPoint(x: nubMaxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
