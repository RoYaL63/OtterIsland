import AppKit
import QuartzCore

/// Fenêtre transparente qui recouvre UN écran pendant le Live. Tout ce que les
/// participants voient en plus de l'écran (dessins, effets, masques) y vit.
///
/// Niveau juste SOUS l'encoche : au-dessus de toutes les apps, mais l'île reste
/// atteignable par-dessus. Elle laisse passer les clics, sauf quand on dessine.
final class LiveOverlayWindow: NSPanel {
    let canvas: LiveCanvasView
    let screenID: CGDirectDisplayID

    init(screen: NSScreen) {
        canvas = LiveCanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))
        screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isMovable = false
        canvas.autoresizingMask = [.width, .height]
        contentView = canvas
        canvas.backingScale = screen.backingScaleFactor
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Point écran (repère AppKit global) → point local au canevas.
    func local(_ screenPoint: NSPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
    }
}

/// Un dessin posé à l'écran.
final class LiveShape {
    let layer: CAShapeLayer
    let createdAt = Date()
    var fadeWork: DispatchWorkItem?
    /// Chemin « épaissi » pour savoir si un clic tombe dessus.
    let hitPath: CGPath

    init(layer: CAShapeLayer, hitPath: CGPath) {
        self.layer = layer
        self.hitPath = hitPath
    }
}

/// Le canevas : dessins, effets de curseur, projecteur et masques, chacun dans
/// son calque. Les animations (fondus, ondes, bulles) sont confiées à Core
/// Animation, qui les fait tourner dans le serveur de rendu sans réveiller l'app.
final class LiveCanvasView: NSView {

    // Rappels vers le contrôleur.
    var onMouseDown: ((LiveCanvasView, CGPoint, NSEvent) -> Void)?
    var onMouseDragged: ((LiveCanvasView, CGPoint) -> Void)?
    var onMouseUp: ((LiveCanvasView, CGPoint) -> Void)?

    var backingScale: CGFloat = 2

    private let masksLayer = CALayer()
    private let drawingsLayer = CALayer()
    private let spotlightLayer = CAShapeLayer()
    private let effectsLayer = CALayer()

    // Effets de curseur
    private let haloLayer = CAShapeLayer()
    private let trailGlowLayer = CAShapeLayer()
    private let trailCoreLayer = CAShapeLayer()
    private let headLayer = CAShapeLayer()
    private let otterLayer = CATextLayer()

    private(set) var shapes: [LiveShape] = []
    private var currentLayer: CAShapeLayer?
    private var currentPoints: [CGPoint] = []
    private var currentTool: LiveTool = .pen
    private var currentStyle: StrokeStyle?

    struct StrokeStyle {
        var color: NSColor
        var width: Double
        var glow: Bool
        var fadeSeconds: Double
        var straighten: Bool
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for sub in [masksLayer, drawingsLayer, spotlightLayer, effectsLayer] {
            sub.frame = bounds
            layer?.addSublayer(sub)
        }
        spotlightLayer.fillRule = .evenOdd
        spotlightLayer.opacity = 0

        for sub in [trailGlowLayer, trailCoreLayer, headLayer, haloLayer] {
            sub.actions = Self.noActions
            effectsLayer.addSublayer(sub)
        }
        otterLayer.actions = Self.noActions
        otterLayer.string = "🦦"
        otterLayer.alignmentMode = .center
        otterLayer.isHidden = true
        effectsLayer.addSublayer(otterLayer)
        spotlightLayer.actions = Self.noActions
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    /// Les déplacements d'effets doivent suivre le curseur à la frame près,
    /// sans l'animation implicite de 0,25 s de Core Animation.
    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "contents": NSNull(),
    ]

    override func layout() {
        super.layout()
        for sub in [masksLayer, drawingsLayer, spotlightLayer, effectsLayer] {
            sub.frame = bounds
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(self, convert(event.locationInWindow, from: nil), event)
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(self, convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(self, convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        onMouseDown?(self, convert(event.locationInWindow, from: nil), event)
    }

    // MARK: - Dessin

    func beginStroke(at point: CGPoint, tool: LiveTool, style: StrokeStyle) {
        let shape = CAShapeLayer()
        shape.actions = Self.noActions
        shape.fillColor = nil
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.strokeColor = style.color.cgColor
        shape.lineWidth = CGFloat(style.width)

        switch tool {
        case .marker:
            shape.lineWidth = CGFloat(style.width) * 4.5
            shape.strokeColor = style.color.withAlphaComponent(0.38).cgColor
            shape.lineCap = .butt
        case .laser:
            shape.strokeColor = NSColor.systemRed.cgColor
            shape.lineWidth = max(4, CGFloat(style.width))
            applyGlow(shape, color: .systemRed, radius: 8)
        default:
            if style.glow { applyGlow(shape, color: style.color, radius: 5) }
        }

        drawingsLayer.addSublayer(shape)
        currentLayer = shape
        currentPoints = [point]
        currentTool = tool
        currentStyle = style
    }

    func continueStroke(to point: CGPoint) {
        guard let layer = currentLayer, let start = currentPoints.first else { return }
        switch currentTool {
        case .pen, .marker:
            currentPoints.append(point)
            layer.path = ShapeRecognizer.smoothPath(currentPoints)
        case .laser:
            // Traînée : seuls les derniers points restent, la queue disparaît
            // pendant que la tête avance.
            currentPoints.append(point)
            if currentPoints.count > 28 { currentPoints.removeFirst(currentPoints.count - 28) }
            layer.path = ShapeRecognizer.smoothPath(currentPoints)
        case .arrow:
            currentPoints = [start, point]
            layer.path = ShapeRecognizer.arrowPath(from: start, to: point, width: Double(layer.lineWidth))
        case .rectangle:
            currentPoints = [start, point]
            layer.path = CGPath(roundedRect: Self.rect(start, point), cornerWidth: 6, cornerHeight: 6, transform: nil)
        case .ellipse:
            currentPoints = [start, point]
            layer.path = CGPath(ellipseIn: Self.rect(start, point), transform: nil)
        }
    }

    /// Termine le trait. Renvoie la forme posée (nil pour le laser, qui ne reste pas).
    @discardableResult
    func endStroke(onFade: @escaping (LiveShape) -> Void) -> LiveShape? {
        guard let layer = currentLayer, let style = currentStyle else { return nil }
        currentLayer = nil
        defer { currentPoints = [] }

        if currentTool == .laser {
            fade(layer, duration: 0.45)
            return nil
        }

        // Clic sans glisser : rien à garder.
        if currentPoints.count < 2 || ShapeRecognizer.pathLength(currentPoints) < 3 {
            layer.removeFromSuperlayer()
            return nil
        }

        if currentTool == .pen, style.straighten {
            switch ShapeRecognizer.recognize(currentPoints) {
            case .line(let a, let b):
                let path = CGMutablePath(); path.move(to: a); path.addLine(to: b)
                layer.path = path
            case .arrow(let a, let b):
                layer.path = ShapeRecognizer.arrowPath(from: a, to: b, width: style.width)
            case .rectangle(let r):
                layer.path = CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)
            case .ellipse(let r):
                layer.path = CGPath(ellipseIn: r, transform: nil)
            case .freehand:
                break
            }
        }

        let path = layer.path ?? CGMutablePath()
        let hit = path.copy(strokingWithWidth: max(18, layer.lineWidth + 12), lineCap: .round, lineJoin: .round, miterLimit: 10)
        let shape = LiveShape(layer: layer, hitPath: hit)
        shapes.append(shape)

        if style.fadeSeconds > 0 {
            let work = DispatchWorkItem { [weak self, weak shape] in
                MainActor.assumeIsolated {
                    guard let self, let shape else { return }
                    self.remove(shape)
                    onFade(shape)
                }
            }
            shape.fadeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + style.fadeSeconds, execute: work)
        }
        return shape
    }

    /// Dessin sous le point, s'il y en a un (le plus récent d'abord).
    func shape(at point: CGPoint) -> LiveShape? {
        shapes.last { $0.hitPath.contains(point) }
    }

    func remove(_ shape: LiveShape) {
        shape.fadeWork?.cancel()
        shapes.removeAll { $0 === shape }
        fade(shape.layer, duration: 0.6)
    }

    func clearAll() {
        for shape in shapes { remove(shape) }
    }

    var latestShape: LiveShape? { shapes.last }

    private func fade(_ layer: CALayer, duration: CFTimeInterval) {
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = 0
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.add(animation, forKey: "fade")
        CATransaction.commit()
    }

    /// Lueur légère. `shadowPath` n'est pas utilisable sur un trait (il suit
    /// le remplissage), d'où une ombre classique : elle n'est recalculée que
    /// quand le chemin change, c'est-à-dire pendant le geste.
    private func applyGlow(_ layer: CAShapeLayer, color: NSColor, radius: CGFloat) {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = 0.75
        layer.shadowRadius = radius
        layer.shadowOffset = .zero
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Effets de curseur

    struct TrailPoint {
        let point: CGPoint
        let time: CFTimeInterval
    }

    func hideCursorEffects() {
        haloLayer.isHidden = true
        trailGlowLayer.path = nil
        trailCoreLayer.path = nil
        headLayer.isHidden = true
        otterLayer.isHidden = true
    }

    func renderHalo(at point: CGPoint, color: NSColor, size: Double) {
        let r = 22 * CGFloat(size)
        haloLayer.isHidden = false
        haloLayer.path = CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2), transform: nil)
        haloLayer.fillColor = color.withAlphaComponent(0.22).cgColor
        haloLayer.strokeColor = color.withAlphaComponent(0.9).cgColor
        haloLayer.lineWidth = 2
    }

    /// Météorite : une traînée effilée, large à la tête et fine à la queue. Elle
    /// garde les 0,3 dernière seconde de trajectoire, donc s'allonge toute
    /// seule quand le geste accélère et se résorbe à l'arrêt.
    func renderMeteor(trail: [TrailPoint], color: NSColor, size: Double) {
        haloLayer.isHidden = true
        otterLayer.isHidden = true
        guard trail.count >= 2, let head = trail.last?.point else {
            trailGlowLayer.path = nil
            trailCoreLayer.path = nil
            headLayer.isHidden = true
            return
        }
        let maxWidth = 9 * CGFloat(size)
        trailCoreLayer.path = Self.taperedPath(trail.map(\.point), maxWidth: maxWidth)
        trailCoreLayer.fillColor = color.withAlphaComponent(0.92).cgColor
        trailGlowLayer.path = Self.taperedPath(trail.map(\.point), maxWidth: maxWidth * 2.4)
        trailGlowLayer.fillColor = color.withAlphaComponent(0.22).cgColor
        let r = maxWidth * 0.75
        headLayer.isHidden = false
        headLayer.path = CGPath(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2), transform: nil)
        headLayer.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
    }

    /// Rivière loutre : un ruban d'eau qui ondule derrière le curseur, des
    /// bulles qui remontent, et la loutre qui nage en tête.
    func renderOtterRiver(trail: [TrailPoint], color: NSColor, size: Double, now: CFTimeInterval) {
        haloLayer.isHidden = true
        headLayer.isHidden = true
        trailGlowLayer.path = nil
        guard trail.count >= 2, let head = trail.last?.point else {
            trailCoreLayer.path = nil
            otterLayer.isHidden = true
            return
        }
        let path = CGMutablePath()
        let pts = trail.map(\.point)
        for (i, p) in pts.enumerated() {
            let prev = pts[max(0, i - 1)], next = pts[min(pts.count - 1, i + 1)]
            let dx = next.x - prev.x, dy = next.y - prev.y
            let len = max(0.001, hypot(dx, dy))
            let nx = -dy / len, ny = dx / len
            let age = now - trail[i].time
            let wave = sin(CGFloat(age) * 18 + CGFloat(i) * 0.55) * 5 * CGFloat(size)
            let q = CGPoint(x: p.x + nx * wave, y: p.y + ny * wave)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        trailCoreLayer.path = path
        trailCoreLayer.fillColor = nil
        trailCoreLayer.strokeColor = color.withAlphaComponent(0.7).cgColor
        trailCoreLayer.lineWidth = 6 * CGFloat(size)
        trailCoreLayer.lineCap = .round
        trailCoreLayer.lineJoin = .round

        let font = 20 * CGFloat(size)
        otterLayer.isHidden = false
        otterLayer.fontSize = font
        otterLayer.contentsScale = backingScale
        otterLayer.frame = CGRect(x: head.x + 10, y: head.y - font - 6, width: font * 1.4, height: font * 1.3)
    }

    /// Une bulle qui remonte et s'évanouit — entièrement animée par Core Animation.
    func spawnBubble(at point: CGPoint, color: NSColor, size: Double) {
        let r = CGFloat.random(in: 2...5) * CGFloat(size)
        let bubble = CAShapeLayer()
        bubble.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        bubble.fillColor = color.withAlphaComponent(0.25).cgColor
        bubble.strokeColor = color.withAlphaComponent(0.85).cgColor
        bubble.lineWidth = 1
        bubble.position = CGPoint(x: point.x + .random(in: -8...8), y: point.y + .random(in: -8...8))
        effectsLayer.addSublayer(bubble)

        let rise = CABasicAnimation(keyPath: "position")
        rise.toValue = NSValue(point: NSPoint(x: bubble.position.x + .random(in: -12...12), y: bubble.position.y + .random(in: 18...34)))
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.6
        grow.toValue = 1.3
        let group = CAAnimationGroup()
        group.animations = [rise, fadeOut, grow]
        group.duration = 0.9
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { bubble.removeFromSuperlayer() }
        bubble.add(group, forKey: "bubble")
        CATransaction.commit()
    }

    /// Onde au clic : un anneau qui s'ouvre et s'efface.
    func spawnRipple(at point: CGPoint, color: NSColor) {
        let ring = CAShapeLayer()
        let r: CGFloat = 9
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2.5
        ring.position = point
        effectsLayer.addSublayer(ring)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 3.6
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fadeOut]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }

    /// Contour d'une traînée effilée : on longe un bord à l'aller, l'autre au retour.
    private static func taperedPath(_ points: [CGPoint], maxWidth: CGFloat) -> CGPath {
        let n = points.count
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<n {
            let prev = points[max(0, i - 1)], next = points[min(n - 1, i + 1)]
            let dx = next.x - prev.x, dy = next.y - prev.y
            let len = max(0.001, hypot(dx, dy))
            let nx = -dy / len, ny = dx / len
            let t = CGFloat(i) / CGFloat(max(1, n - 1))
            let w = maxWidth * pow(t, 0.9) / 2
            left.append(CGPoint(x: points[i].x + nx * w, y: points[i].y + ny * w))
            right.append(CGPoint(x: points[i].x - nx * w, y: points[i].y - ny * w))
        }
        let path = CGMutablePath()
        path.addLines(between: left + right.reversed())
        path.closeSubpath()
        return path
    }

    // MARK: - Projecteur

    func renderSpotlight(at point: CGPoint?, radius: Double, darkness: Double) {
        guard let point else {
            spotlightLayer.opacity = 0
            return
        }
        let r = CGFloat(radius)
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        spotlightLayer.path = path
        spotlightLayer.fillColor = NSColor.black.withAlphaComponent(CGFloat(darkness)).cgColor
        spotlightLayer.opacity = 1
    }

    // MARK: - Masques

    enum MaskKind { case secret, app }

    /// Remplace tous les masques. Appelé deux fois par seconde au plus : on
    /// reconstruit plutôt que de suivre chaque rectangle.
    func renderMasks(_ masks: [(CGRect, MaskKind)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        masksLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        for (rect, kind) in masks {
            let box = CALayer()
            box.frame = rect
            box.cornerRadius = kind == .app ? 10 : 4
            box.backgroundColor = NSColor(srgbRed: 0.07, green: 0.12, blue: 0.12, alpha: 1).cgColor
            box.borderColor = NSColor(srgbRed: 0.37, green: 0.91, blue: 0.83, alpha: 0.6).cgColor
            box.borderWidth = 1

            let label = CATextLayer()
            label.string = kind == .app ? "🔒 Masqué pendant le Live" : "🔒 masqué"
            label.fontSize = kind == .app ? 14 : max(9, min(12, rect.height * 0.6))
            label.foregroundColor = NSColor(srgbRed: 0.37, green: 0.91, blue: 0.83, alpha: 1).cgColor
            label.alignmentMode = .center
            label.contentsScale = backingScale
            let h = label.fontSize * 1.35
            label.frame = CGRect(x: 0, y: (rect.height - h) / 2, width: rect.width, height: h)
            box.addSublayer(label)
            masksLayer.addSublayer(box)
        }
        CATransaction.commit()
    }
}
