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
    let layer: CALayer
    let createdAt = Date()
    var fadeWork: DispatchWorkItem?
    /// Chemin « épaissi » pour savoir si un clic tombe dessus.
    var hitPath: CGPath
    /// Pastille numérotée : son numéro, et l'étiquette éventuelle.
    var badgeNumber: Int?
    var label: String = ""

    init(layer: CALayer, hitPath: CGPath) {
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
    /// Étincelles : système de particules entièrement calculé par le serveur
    /// de rendu. L'app ne fait que déplacer son point d'émission.
    private let sparkEmitter = CAEmitterLayer()
    /// Distance parcourue depuis le dernier point du sillage « Pointillés ».
    private var dotDistance: CGFloat = 0
    private var lastDotPoint: CGPoint?

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
        sparkEmitter.actions = Self.noActions
        sparkEmitter.emitterShape = .point
        sparkEmitter.renderMode = .additive
        sparkEmitter.birthRate = 0
        effectsLayer.addSublayer(sparkEmitter)
        spotlightLayer.actions = Self.noActions
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non utilisé") }

    /// Les déplacements d'effets doivent suivre le curseur à la frame près,
    /// sans l'animation implicite de 0,25 s de Core Animation.
    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "path": NSNull(), "opacity": NSNull(),
        "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "contents": NSNull(),
        "emitterPosition": NSNull(), "birthRate": NSNull(), "emitterCells": NSNull(),
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

    // MARK: - Pastilles

    static let badgeRadius: CGFloat = 13

    /// Pose une pastille numérotée centrée sur `point`. Elle reste jusqu'à
    /// l'effacement, sauf si `fadeSeconds` > 0.
    func placeBadge(at point: CGPoint, number: Int, color: NSColor, fadeSeconds: Double, onFade: @escaping (LiveShape) -> Void) -> LiveShape {
        let r = Self.badgeRadius
        let container = CALayer()
        container.actions = Self.noActions
        container.frame = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)

        let circle = CAShapeLayer()
        circle.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: r * 2, height: r * 2), transform: nil)
        circle.fillColor = color.cgColor
        circle.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        circle.lineWidth = 2
        circle.shadowColor = NSColor.black.cgColor
        circle.shadowOpacity = 0.35
        circle.shadowRadius = 4
        circle.shadowOffset = CGSize(width: 0, height: -1)
        circle.shadowPath = circle.path
        container.addSublayer(circle)

        let text = CATextLayer()
        text.string = "\(number)"
        text.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        text.fontSize = number >= 10 ? 11 : 13
        text.alignmentMode = .center
        text.foregroundColor = Self.contrastingText(for: color).cgColor
        text.contentsScale = backingScale
        let h = text.fontSize * 1.25
        text.frame = CGRect(x: 0, y: r - h / 2 - 1, width: r * 2, height: h)
        container.addSublayer(text)

        drawingsLayer.addSublayer(container)
        let shape = LiveShape(layer: container, hitPath: CGPath(ellipseIn: container.frame.insetBy(dx: -4, dy: -4), transform: nil))
        shape.badgeNumber = number
        shapes.append(shape)

        // Apparition : un petit rebond, joué par Core Animation.
        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.4
        pop.toValue = 1
        pop.damping = 12
        pop.initialVelocity = 8
        pop.duration = pop.settlingDuration
        container.add(pop, forKey: "pop")

        if fadeSeconds > 0 {
            let work = DispatchWorkItem { [weak self, weak shape] in
                MainActor.assumeIsolated {
                    guard let self, let shape else { return }
                    self.remove(shape)
                    onFade(shape)
                }
            }
            shape.fadeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeSeconds, execute: work)
        }
        return shape
    }

    /// Étiquette à droite de la pastille : texte blanc sur une bulle sombre.
    /// Une étiquette vide retire la bulle.
    func setLabel(_ label: String, on shape: LiveShape) {
        guard shape.badgeNumber != nil else { return }
        shape.label = label
        let r = Self.badgeRadius
        shape.layer.sublayers?.filter { $0.name == "label" }.forEach { $0.removeFromSuperlayer() }
        let center = CGPoint(x: shape.layer.frame.midX, y: shape.layer.frame.midY)
        guard !label.isEmpty else {
            shape.hitPath = CGPath(ellipseIn: shape.layer.frame.insetBy(dx: -4, dy: -4), transform: nil)
            return
        }
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let width = ceil((label as NSString).size(withAttributes: [.font: font]).width) + 20
        let height: CGFloat = 26

        let bubble = CALayer()
        bubble.name = "label"
        bubble.actions = Self.noActions
        bubble.frame = CGRect(x: r * 2 + 6, y: r - height / 2, width: width, height: height)
        bubble.backgroundColor = NSColor(srgbRed: 0.06, green: 0.08, blue: 0.09, alpha: 0.88).cgColor
        bubble.cornerRadius = height / 2
        bubble.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        bubble.borderWidth = 1

        let text = CATextLayer()
        text.string = label
        text.font = font
        text.fontSize = 14
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.contentsScale = backingScale
        text.frame = CGRect(x: 0, y: (height - 18) / 2 - 1, width: width, height: 18)
        bubble.addSublayer(text)
        shape.layer.addSublayer(bubble)

        let hit = CGMutablePath()
        hit.addEllipse(in: CGRect(x: center.x - r - 4, y: center.y - r - 4, width: r * 2 + 8, height: r * 2 + 8))
        hit.addRect(CGRect(x: shape.layer.frame.minX + bubble.frame.minX, y: shape.layer.frame.minY + bubble.frame.minY, width: width, height: height))
        shape.hitPath = hit
    }

    /// Point d'ancrage de l'étiquette, en repère local du canevas.
    func labelAnchor(for shape: LiveShape) -> CGPoint {
        CGPoint(x: shape.layer.frame.maxX + 6, y: shape.layer.frame.midY)
    }

    var badges: [LiveShape] { shapes.filter { $0.badgeNumber != nil } }

    /// Texte noir sur une pastille claire (jaune, blanc), blanc sinon.
    private static func contrastingText(for color: NSColor) -> NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.65 ? .black : .white
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
        sparkEmitter.birthRate = 0
        lastDotPoint = nil
        dotDistance = 0
    }

    /// Anneau fin : un cercle de 1,5 pt autour de la pointe, sans remplissage.
    /// Il signale le curseur sans le noyer sous une pastille.
    func renderRing(at point: CGPoint, color: NSColor, size: Double) {
        let r = 13 * CGFloat(size)
        haloLayer.isHidden = false
        haloLayer.path = CGPath(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2), transform: nil)
        haloLayer.fillColor = nil
        haloLayer.strokeColor = color.withAlphaComponent(0.9).cgColor
        haloLayer.lineWidth = 1.5
        haloLayer.shadowColor = color.cgColor
        haloLayer.shadowOpacity = 0.6
        haloLayer.shadowRadius = 3
        haloLayer.shadowOffset = .zero
    }

    /// Comète : UNE traînée continue, effilée, avec une tête blanche. Elle
    /// garde les 0,3 dernière seconde de trajectoire, donc s'allonge toute
    /// seule quand le geste accélère et se résorbe à l'arrêt.
    func renderComet(trail: [TrailPoint], color: NSColor, size: Double) {
        haloLayer.isHidden = true
        guard trail.count >= 2, let head = trail.last?.point else {
            trailGlowLayer.path = nil
            trailCoreLayer.path = nil
            headLayer.isHidden = true
            return
        }
        let points = Self.smoothed(trail.map(\.point))
        let maxWidth = 9 * CGFloat(size)
        trailCoreLayer.path = Self.taperedPath(points, maxWidth: maxWidth)
        trailCoreLayer.fillColor = color.withAlphaComponent(0.92).cgColor
        trailCoreLayer.strokeColor = nil
        trailGlowLayer.path = Self.taperedPath(points, maxWidth: maxWidth * 2.4)
        trailGlowLayer.fillColor = color.withAlphaComponent(0.22).cgColor
        let r = maxWidth * 0.75
        headLayer.isHidden = false
        headLayer.path = CGPath(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2), transform: nil)
        headLayer.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
    }

    /// Étincelles : pas de ligne du tout — des points de lumière jaillissent
    /// du curseur, s'éparpillent, tombent un peu et scintillent en s'éteignant.
    /// Rien n'est émis quand la souris est immobile.
    func emitSparks(at point: CGPoint, color: NSColor, size: Double, speed: CGFloat) {
        haloLayer.isHidden = true
        trailGlowLayer.path = nil
        trailCoreLayer.path = nil
        headLayer.isHidden = true
        if sparkEmitter.emitterCells == nil || sparkEmitter.emitterCells?.first?.name != color.hexString + "\(size)" {
            sparkEmitter.emitterCells = [Self.sparkCell(color: color, size: size)]
            sparkEmitter.beginTime = CACurrentMediaTime()
        }
        sparkEmitter.emitterPosition = point
        // Plus le geste est rapide, plus il y a d'étincelles (plafonné).
        sparkEmitter.birthRate = Float(min(3, max(0.6, speed / 400)))
    }

    func stopSparks() {
        sparkEmitter.birthRate = 0
    }

    private static func sparkCell(color: NSColor, size: Double) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = color.hexString + "\(size)"
        cell.contents = sparkImage
        cell.birthRate = 90
        cell.lifetime = 0.75
        cell.lifetimeRange = 0.25
        cell.velocity = 55
        cell.velocityRange = 40
        cell.emissionRange = .pi * 2
        cell.yAcceleration = -140
        cell.scale = 0.16 * CGFloat(size)
        cell.scaleRange = 0.08 * CGFloat(size)
        cell.scaleSpeed = -0.18 * CGFloat(size)
        cell.alphaSpeed = -1.25
        cell.spin = 3
        cell.spinRange = 6
        cell.color = color.cgColor
        cell.redRange = 0.15
        cell.greenRange = 0.15
        cell.blueRange = 0.15
        return cell
    }

    /// Étoile douce à quatre branches, dessinée une fois.
    private static let sparkImage: CGImage? = {
        let side = 64
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let c = CGFloat(side) / 2
        // Cœur flou
        let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
            locations: [0, 1]
        )
        if let glow {
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: c, y: c), startRadius: 0, endCenter: CGPoint(x: c, y: c), endRadius: c * 0.55, options: [])
        }
        // Branches
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        let star = CGMutablePath()
        star.move(to: CGPoint(x: c, y: 0))
        star.addQuadCurve(to: CGPoint(x: CGFloat(side), y: c), control: CGPoint(x: c, y: c))
        star.addQuadCurve(to: CGPoint(x: c, y: CGFloat(side)), control: CGPoint(x: c, y: c))
        star.addQuadCurve(to: CGPoint(x: 0, y: c), control: CGPoint(x: c, y: c))
        star.addQuadCurve(to: CGPoint(x: c, y: 0), control: CGPoint(x: c, y: c))
        ctx.addPath(star)
        ctx.fillPath()
        return ctx.makeImage()
    }()

    /// Pointillés : un point posé tous les 16 pt parcourus, qui rétrécit et
    /// s'efface. Le chemin se lit comme une série d'empreintes, sans ligne.
    func dropDots(at point: CGPoint, color: NSColor, size: Double) {
        haloLayer.isHidden = true
        trailGlowLayer.path = nil
        trailCoreLayer.path = nil
        headLayer.isHidden = true
        guard let last = lastDotPoint else {
            lastDotPoint = point
            spawnDot(at: point, color: color, size: size)
            return
        }
        dotDistance += hypot(point.x - last.x, point.y - last.y)
        lastDotPoint = point
        let spacing = 16 * CGFloat(size)
        if dotDistance >= spacing {
            dotDistance = 0
            spawnDot(at: point, color: color, size: size)
        }
    }

    private func spawnDot(at point: CGPoint, color: NSColor, size: Double) {
        let r = 4 * CGFloat(size)
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        dot.fillColor = color.cgColor
        dot.position = point
        effectsLayer.addSublayer(dot)
        animateOut(dot, duration: 0.8, keyframes: [
            ("transform.scale", 1.0, 0.15),
            ("opacity", 1.0, 0.0),
        ])
    }

    /// Lissage de Chaikin (deux passes) : la trajectoire brute de la souris
    /// est faite de segments ; lissée, la traînée coule au lieu de zigzaguer.
    private static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var current = points
        for _ in 0..<2 {
            var next: [CGPoint] = [current[0]]
            for i in 0..<(current.count - 1) {
                let a = current[i], b = current[i + 1]
                next.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
                next.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
            }
            next.append(current[current.count - 1])
            current = next
        }
        return current
    }

    // MARK: - Clics

    enum ClickKind { case left, double, right }

    /// Une forme différente par bouton, dans la même couleur :
    /// - clic gauche : un anneau net qui s'ouvre ;
    /// - double-clic : deux anneaux décalés, comme un écho ;
    /// - clic droit : un losange qui tourne d'un quart de tour en s'agrandissant.
    func spawnClick(_ kind: ClickKind, at point: CGPoint, color: NSColor) {
        switch kind {
        case .left:
            spawnRing(at: point, color: color, delay: 0)
        case .double:
            spawnRing(at: point, color: color, delay: 0)
            spawnRing(at: point, color: color, delay: 0.12)
        case .right:
            let side: CGFloat = 14
            let diamond = CAShapeLayer()
            diamond.path = CGPath(roundedRect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side), cornerWidth: 3, cornerHeight: 3, transform: nil)
            diamond.fillColor = color.withAlphaComponent(0.18).cgColor
            diamond.strokeColor = color.cgColor
            diamond.lineWidth = 2
            diamond.position = point
            diamond.transform = CATransform3DMakeRotation(.pi / 4, 0, 0, 1)
            effectsLayer.addSublayer(diamond)
            animateOut(diamond, duration: 0.5, keyframes: [
                ("transform.scale", 1.0, 2.8),
                ("transform.rotation.z", Double.pi / 4, Double.pi * 0.75),
                ("opacity", 1.0, 0.0),
            ])
        }
    }

    private func spawnRing(at point: CGPoint, color: NSColor, delay: CFTimeInterval) {
        let r: CGFloat = 8
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2
        ring.position = point
        ring.opacity = delay > 0 ? 0 : 1
        effectsLayer.addSublayer(ring)
        animateOut(ring, duration: 0.45, delay: delay, keyframes: [
            ("transform.scale", 1.0, 3.4),
            ("opacity", 1.0, 0.0),
        ])
    }

    /// Anime un calque de passage puis le retire — tout se joue dans le
    /// serveur de rendu.
    private func animateOut(_ layer: CALayer, duration: CFTimeInterval, delay: CFTimeInterval = 0, keyframes: [(String, Double, Double)]) {
        let group = CAAnimationGroup()
        group.animations = keyframes.map { key, from, to in
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = to
            return animation
        }
        group.duration = duration
        group.beginTime = CACurrentMediaTime() + delay
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        // `.forwards` et non `.both` : un anneau retardé (double-clic) doit
        // rester invisible pendant son délai au lieu d'apparaître figé.
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.add(group, forKey: "out")
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
