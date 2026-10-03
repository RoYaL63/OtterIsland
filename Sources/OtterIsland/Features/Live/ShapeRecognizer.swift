import CoreGraphics
import Foundation

/// Redresse un trait à main levée : une ligne presque droite devient droite
/// (une flèche si elle finit en crochet), une boucle fermée devient un cercle
/// ou un rectangle propre. Le reste est laissé tel quel — mieux vaut un trait
/// fidèle qu'une forme devinée de travers.
///
/// Heuristiques simples, sans apprentissage : quelques divisions par trait,
/// calculées une fois au relâchement du clic.
enum ShapeRecognizer {

    enum Result {
        case line(CGPoint, CGPoint)
        case arrow(CGPoint, CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case freehand
    }

    static func recognize(_ points: [CGPoint]) -> Result {
        guard points.count >= 6, let first = points.first, let last = points.last else { return .freehand }
        let length = pathLength(points)
        guard length > 40 else { return .freehand }

        let bounds = boundingBox(points)
        let closed = distance(first, last) < max(24, length * 0.12)

        if closed, bounds.width > 24, bounds.height > 24 {
            if isEllipse(points, in: bounds) { return .ellipse(bounds) }
            if isRectangle(points, in: bounds) { return .rectangle(bounds) }
            return .freehand
        }

        // Ligne : tous les points restent près de la corde.
        let deviation = points.map { distanceToSegment($0, first, last) }.max() ?? 0
        if deviation < max(8, distance(first, last) * 0.08) {
            return .line(first, last)
        }

        // Flèche dessinée d'un seul trait : un long segment droit puis un
        // crochet court qui revient en arrière. On cherche le point le plus
        // éloigné du départ : c'est la pointe.
        if let tipIndex = points.indices.max(by: { distance(first, points[$0]) < distance(first, points[$1]) }),
           tipIndex > points.count / 2, tipIndex < points.count - 2 {
            let tip = points[tipIndex]
            let shaft = Array(points[...tipIndex])
            let shaftDeviation = shaft.map { distanceToSegment($0, first, tip) }.max() ?? 0
            let hookLength = pathLength(Array(points[tipIndex...]))
            let shaftLength = distance(first, tip)
            if shaftDeviation < max(10, shaftLength * 0.1), hookLength < shaftLength * 0.6, hookLength > 8 {
                return .arrow(first, tip)
            }
        }
        return .freehand
    }

    // MARK: Tests de forme

    /// Distance au centre ramenée aux demi-axes : ≈ 1 pour tous les points d'une ellipse.
    private static func isEllipse(_ points: [CGPoint], in r: CGRect) -> Bool {
        let cx = r.midX, cy = r.midY, a = r.width / 2, b = r.height / 2
        guard a > 0, b > 0 else { return false }
        let errors = points.map { p -> Double in
            let nx = Double((p.x - cx) / a), ny = Double((p.y - cy) / b)
            return abs(sqrt(nx * nx + ny * ny) - 1)
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        return mean < 0.14
    }

    /// Les points longent les bords de la boîte englobante.
    private static func isRectangle(_ points: [CGPoint], in r: CGRect) -> Bool {
        let minSide = min(r.width, r.height)
        let errors = points.map { p -> Double in
            Double(min(abs(p.x - r.minX), abs(p.x - r.maxX), abs(p.y - r.minY), abs(p.y - r.maxY)))
        }
        let mean = errors.reduce(0, +) / Double(errors.count)
        return mean < Double(minSide) * 0.1
    }

    // MARK: Géométrie

    static func pathLength(_ points: [CGPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return distance(p, a) }
        let t: CGFloat = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    // MARK: Chemins

    /// Tige + pointe en V, la pointe proportionnée à l'épaisseur du trait.
    static func arrowPath(from a: CGPoint, to b: CGPoint, width: Double) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        let angle: CGFloat = atan2(b.y - a.y, b.x - a.x)
        let head: CGFloat = max(14, CGFloat(width) * 4)
        let spread: CGFloat = 0.45
        path.move(to: CGPoint(x: b.x - head * cos(angle - spread), y: b.y - head * sin(angle - spread)))
        path.addLine(to: b)
        path.addLine(to: CGPoint(x: b.x - head * cos(angle + spread), y: b.y - head * sin(angle + spread)))
        return path
    }

    /// Trait lissé (Catmull-Rom → Bézier) : la main tremble, le trait non.
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}
