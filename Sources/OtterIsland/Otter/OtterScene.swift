import SpriteKit

/// Scène SpriteKit de la loutre : respiration, balancement, expressions et effets
/// selon l'humeur (Zzz endormie, étincelles curieuse, bulles en nage).
final class OtterScene: SKScene {
    private var otter: SKSpriteNode?
    private var tail: SKSpriteNode?
    private var otterSide: CGFloat = 60
    private(set) var mood: OtterMood = .idle
    private var textureCache: [OtterFace: SKTexture] = [:]
    private lazy var swimTexture: SKTexture = PixelArt.texture(
        from: OtterSprites.swim, palette: PixelArt.otterPalette
    )

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non supporté")
    }

    private var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2)
    }

    override func didMove(to view: SKView) {
        setupOtter()
        applyMood(.idle)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        otter?.position = center
    }

    // MARK: Textures

    private func texture(for face: OtterFace) -> SKTexture {
        if let cached = textureCache[face] { return cached }
        let made = PixelArt.texture(from: OtterSprites.grid(for: face), palette: PixelArt.otterPalette)
        textureCache[face] = made
        return made
    }

    // MARK: Setup

    private func setupOtter() {
        guard otter == nil else { return }
        let node = SKSpriteNode(texture: texture(for: .neutral))
        node.texture?.filteringMode = .nearest
        otterSide = min(size.width, size.height) * 0.9
        node.size = CGSize(width: otterSide, height: otterSide)
        node.position = center
        addChild(node)
        otter = node

        addTail(to: node)
        scheduleBlink()
    }

    /// Petite queue accrochée en bas de la loutre, qui bat doucement.
    private func addTail(to body: SKSpriteNode) {
        let tailNode = SKSpriteNode(
            color: PixelArt.otterPalette[1],
            size: CGSize(width: otterSide * 0.18, height: otterSide * 0.1)
        )
        tailNode.anchorPoint = CGPoint(x: 1, y: 0.5) // pivote depuis le corps
        // Attachée au flanc bas-gauche du corps (sprite 20x20 : bord du corps
        // vers la colonne 1, rangée 15).
        tailNode.position = CGPoint(x: -otterSide * 0.38, y: -otterSide * 0.26)
        tailNode.zPosition = -1
        body.addChild(tailNode)
        tail = tailNode

        let wag = SKAction.sequence([
            .rotate(toAngle: 0.5, duration: 0.4),
            .rotate(toAngle: -0.1, duration: 0.4),
        ])
        wag.timingMode = .easeInEaseOut
        tailNode.run(.repeatForever(wag), withKey: "wag")
    }

    // MARK: Humeur

    func update(mood: OtterMood) {
        guard mood != self.mood else { return }
        applyMood(mood)
    }

    private func applyMood(_ mood: OtterMood) {
        self.mood = mood
        clearEffects()
        setFace(mood.face)
        startBob()
        startBreathing()

        switch mood {
        case .curious:
            hop()
            startSparkle()
        case .happy, .playful:
            wiggle()
        case .swimming:
            startSwim()
        case .worried:
            startWorried()
        case .sleepy:
            startZzz()
        case .cleaning:
            startCleaning()
        case .overloaded:
            startOverloaded()
        case .focused:
            startFocused()
        case .meetingSoon:
            startMeetingSoon()
        case .night:
            startNight()
        case .idle:
            break
        }
    }

    /// Texture courante : pose de nage dédiée si musique, sinon l'expression.
    private func currentTexture() -> SKTexture {
        mood == .swimming ? swimTexture : texture(for: mood.face)
    }

    private func setFace(_ face: OtterFace) {
        guard let otter else { return }
        otter.texture = currentTexture()
        otter.size = CGSize(width: otterSide, height: otterSide) // le setter texture peut retailler
        tail?.isHidden = (mood == .swimming) // la queue gêne la pose de nage
    }

    // MARK: Animations continues

    private func startBob() {
        guard let otter else { return }
        otter.removeAction(forKey: "bob")
        otter.position = center
        let up = SKAction.moveBy(x: 0, y: 3, duration: mood.bobDuration / 2)
        up.timingMode = .easeInEaseOut
        otter.run(.repeatForever(.sequence([up, up.reversed()])), withKey: "bob")
    }

    private func startBreathing() {
        guard let otter else { return }
        otter.removeAction(forKey: "breathe")
        let inhale = SKAction.scale(to: 1.05, duration: mood.bobDuration / 2)
        inhale.timingMode = .easeInEaseOut
        let exhale = SKAction.scale(to: 1.0, duration: mood.bobDuration / 2)
        exhale.timingMode = .easeInEaseOut
        otter.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathe")
    }

    private func scheduleBlink() {
        let wait = SKAction.wait(forDuration: 2.5, withRange: 2.0)
        let blink = SKAction.run { [weak self] in self?.doBlink() }
        run(.repeatForever(.sequence([wait, blink])), withKey: "blink")
    }

    private func doBlink() {
        // Pas de clignement quand elle dort (yeux mi-clos) ni en nage (pose dédiée).
        guard let otter, mood != .sleepy, mood != .swimming else { return }
        otter.run(.sequence([
            .setTexture(texture(for: .blink)),
            .wait(forDuration: 0.12),
            .setTexture(currentTexture()),
        ]))
    }

    // MARK: Réactions ponctuelles

    private func hop() {
        guard let otter else { return }
        let hop = SKAction.sequence([
            .moveBy(x: 0, y: 8, duration: 0.15),
            .moveBy(x: 0, y: -8, duration: 0.15),
        ])
        otter.run(.repeat(hop, count: 2))
    }

    private func wiggle() {
        guard let otter else { return }
        otter.run(.sequence([
            .rotate(byAngle: 0.14, duration: 0.1),
            .rotate(byAngle: -0.28, duration: 0.2),
            .rotate(byAngle: 0.14, duration: 0.1),
        ]))
    }

    private func startSwim() {
        guard let otter else { return }
        let sway = SKAction.sequence([
            .moveBy(x: 6, y: 0, duration: 0.6),
            .moveBy(x: -12, y: 0, duration: 1.2),
            .moveBy(x: 6, y: 0, duration: 0.6),
        ])
        sway.timingMode = .easeInEaseOut
        otter.run(.repeatForever(sway), withKey: "swim")
        startBubbles()
        startNotes()
    }

    /// Notes de musique qui s'élèvent pendant la nage.
    private func startNotes() {
        let spawn = SKAction.run { [weak self] in self?.spawnNote() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 1.1)])), withKey: "notes")
    }

    private func spawnNote() {
        let note = SKLabelNode(text: Bool.random() ? "♪" : "♫")
        note.name = "fx"
        note.fontName = "Menlo"
        note.fontSize = 11
        note.fontColor = SKColor(white: 1, alpha: 0.85)
        note.alpha = 0
        note.position = CGPoint(
            x: size.width * CGFloat.random(in: 0.25...0.75),
            y: size.height * 0.62
        )
        addChild(note)
        note.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .group([
                .moveBy(x: CGFloat.random(in: -6...6), y: 18, duration: 1.4),
                .sequence([.wait(forDuration: 0.7), .fadeOut(withDuration: 0.7)]),
            ]),
            .removeFromParent(),
        ]))
    }

    /// Va-et-vient façon "coup de chiffon", avec de petites étincelles de propreté.
    private func startCleaning() {
        guard let otter else { return }
        let wipe = SKAction.sequence([
            .moveBy(x: 9, y: 0, duration: 0.16),
            .moveBy(x: -18, y: 0, duration: 0.32),
            .moveBy(x: 9, y: 0, duration: 0.16),
        ])
        wipe.timingMode = .easeInEaseOut
        otter.run(.repeatForever(wipe), withKey: "clean")

        let spawn = SKAction.run { [weak self] in self?.spawnCleanMark() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 0.3)])), withKey: "cleanmarks")
    }

    private func spawnCleanMark() {
        // Alterne étincelles de propreté et bulles de savon.
        let label = SKLabelNode(text: Bool.random() ? "✨" : "🫧")
        label.name = "fx"
        label.fontSize = 9
        label.alpha = 0
        label.position = CGPoint(
            x: size.width * 0.5 + CGFloat.random(in: -14...14),
            y: size.height * 0.32
        )
        addChild(label)
        label.run(.sequence([
            .fadeIn(withDuration: 0.1),
            .wait(forDuration: 0.15),
            .fadeOut(withDuration: 0.2),
            .removeFromParent(),
        ]))
    }

    // MARK: RAM saturée : elle halète, s'évente et transpire

    private func startOverloaded() {
        guard let otter else { return }
        // Petit tremblement latéral rapide, comme un moteur qui peine.
        let jitter = SKAction.sequence([
            .moveBy(x: 2.5, y: 0, duration: 0.06),
            .moveBy(x: -5, y: 0, duration: 0.12),
            .moveBy(x: 2.5, y: 0, duration: 0.06),
            .wait(forDuration: 0.5),
        ])
        otter.run(.repeatForever(jitter), withKey: "jitter")

        let spawn = SKAction.run { [weak self] in self?.spawnSweat() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 0.9)])), withKey: "sweat")
    }

    private func spawnSweat() {
        let drop = SKLabelNode(text: "💦")
        drop.name = "fx"
        drop.fontSize = 10
        drop.alpha = 0
        // Alternance des deux tempes.
        let side: CGFloat = Bool.random() ? 0.3 : 0.7
        drop.position = CGPoint(x: size.width * side, y: size.height * 0.68)
        addChild(drop)
        drop.run(.sequence([
            .fadeIn(withDuration: 0.1),
            .group([
                .moveBy(x: side < 0.5 ? -8 : 8, y: -6, duration: 0.7),
                .fadeOut(withDuration: 0.7),
            ]),
            .removeFromParent(),
        ]))
    }

    // MARK: Concentration : casque sur les oreilles, elle ne bouge plus

    /// Pomodoro en cours. Rien qui clignote ni qui saute : la loutre doit
    /// signaler « je bosse » sans redevenir elle-même une source de
    /// distraction — ce serait contredire la fonctionnalité qu'elle annonce.
    private func startFocused() {
        guard let otter else { return }
        let headphones = SKLabelNode(text: "🎧")
        headphones.name = "fx"
        headphones.fontSize = 13
        headphones.position = CGPoint(x: 0, y: otterSide * 0.30)
        headphones.zPosition = 2
        otter.addChild(headphones)

        // Un souffle très lent, à peine perceptible, plutôt qu'une animation.
        let pulse = SKAction.sequence([
            .fadeAlpha(to: 0.75, duration: 1.6),
            .fadeAlpha(to: 1.0, duration: 1.6),
        ])
        pulse.timingMode = .easeInEaseOut
        headphones.run(.repeatForever(pulse))
    }

    // MARK: RDV imminent : elle regarde l'heure

    private func startMeetingSoon() {
        guard let otter else { return }
        // Elle se penche d'un côté puis de l'autre, comme on cherche l'horloge.
        let lean = SKAction.sequence([
            .rotate(toAngle: 0.10, duration: 0.5),
            .rotate(toAngle: -0.10, duration: 0.5),
        ])
        lean.timingMode = .easeInEaseOut
        otter.run(.repeatForever(lean), withKey: "lean")

        let spawn = SKAction.run { [weak self] in self?.spawnClock() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 1.6)])), withKey: "clock")
    }

    private func spawnClock() {
        let clock = SKLabelNode(text: "⏰")
        clock.name = "fx"
        clock.fontSize = 12
        clock.alpha = 0
        clock.position = CGPoint(x: size.width * 0.68, y: size.height * 0.66)
        addChild(clock)
        clock.run(.sequence([
            .fadeIn(withDuration: 0.15),
            .group([
                .sequence([
                    .rotate(byAngle: 0.25, duration: 0.08),
                    .rotate(byAngle: -0.5, duration: 0.16),
                    .rotate(byAngle: 0.25, duration: 0.08),
                ]),
                .sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.4)]),
            ]),
            .removeFromParent(),
        ]))
    }

    // MARK: Nuit : la lune est là, elle bâille

    private func startNight() {
        let moon = SKLabelNode(text: "🌙")
        moon.name = "fx"
        moon.fontSize = 12
        moon.alpha = 0.85
        moon.position = CGPoint(x: size.width * 0.76, y: size.height * 0.76)
        addChild(moon)

        // Bien plus espacé que les Zzz de `sleepy` : la nuit, elle somnole,
        // elle ne dort pas encore.
        let spawn = SKAction.run { [weak self] in self?.spawnZ() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 3.4)])), withKey: "zzz")
    }

    // MARK: Effets (nodes nommés "fx")

    private func clearEffects() {
        for key in ["zzz", "sparkle", "bubbles", "drops", "cleanmarks", "notes", "sweat", "clock"] {
            removeAction(forKey: key)
        }
        otter?.removeAction(forKey: "swim")
        otter?.removeAction(forKey: "shiver")
        otter?.removeAction(forKey: "clean")
        otter?.removeAction(forKey: "jitter")
        otter?.removeAction(forKey: "lean")
        otter?.zRotation = 0
        enumerateChildNodes(withName: "fx") { node, _ in node.removeFromParent() }
        // Les effets accrochés AU CORPS (casque de concentration) ne sont pas
        // des enfants de la scène : sans cette seconde passe, le casque restait
        // sur les oreilles après la fin du Pomodoro.
        otter?.enumerateChildNodes(withName: "fx") { node, _ in node.removeFromParent() }
    }

    private func startZzz() {
        let spawn = SKAction.run { [weak self] in self?.spawnZ() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 1.4)])), withKey: "zzz")
    }

    private func spawnZ() {
        let label = SKLabelNode(text: "z")
        label.name = "fx"
        label.fontName = "Menlo-Bold"
        label.fontSize = 12
        label.fontColor = SKColor(white: 1, alpha: 0.85)
        label.position = CGPoint(x: size.width * 0.62, y: size.height * 0.62)
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 10, y: 20, duration: 1.6), .fadeOut(withDuration: 1.6)]),
            .removeFromParent(),
        ]))
    }

    private func startSparkle() {
        let spawn = SKAction.run { [weak self] in self?.spawnSparkle() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 0.9)])), withKey: "sparkle")
    }

    private func spawnSparkle() {
        let label = SKLabelNode(text: "✨")
        label.name = "fx"
        label.fontSize = 12
        label.alpha = 0
        label.position = CGPoint(x: size.width * 0.66, y: size.height * 0.66)
        addChild(label)
        label.run(.sequence([
            .fadeIn(withDuration: 0.2),
            .wait(forDuration: 0.3),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    private func startBubbles() {
        let spawn = SKAction.run { [weak self] in self?.spawnBubble() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 0.7)])), withKey: "bubbles")
    }

    private func spawnBubble() {
        let bubble = SKShapeNode(circleOfRadius: 2)
        bubble.name = "fx"
        bubble.strokeColor = SKColor(white: 1, alpha: 0.5)
        bubble.fillColor = .clear
        bubble.position = CGPoint(
            x: size.width * 0.5 + CGFloat.random(in: -12...12),
            y: size.height * 0.3
        )
        addChild(bubble)
        bubble.run(.sequence([
            .group([.moveBy(x: 0, y: 24, duration: 1.4), .fadeOut(withDuration: 1.4)]),
            .removeFromParent(),
        ]))
    }

    // MARK: Batterie faible : elle se planque et tremble

    private func startWorried() {
        guard let otter else { return }
        otter.run(.moveBy(x: 0, y: -5, duration: 0.2)) // s'accroupit
        let shiver = SKAction.sequence([
            .rotate(toAngle: 0.06, duration: 0.07),
            .rotate(toAngle: -0.06, duration: 0.07),
        ])
        otter.run(.repeatForever(shiver), withKey: "shiver")
        startDrops()
    }

    private func startDrops() {
        let spawn = SKAction.run { [weak self] in self?.spawnDrop() }
        run(.repeatForever(.sequence([spawn, .wait(forDuration: 1.2)])), withKey: "drops")
    }

    private func spawnDrop() {
        let drop = SKLabelNode(text: "💧")
        drop.name = "fx"
        drop.fontSize = 11
        drop.position = CGPoint(x: size.width * 0.64, y: size.height * 0.6)
        addChild(drop)
        drop.run(.sequence([
            .group([.moveBy(x: 6, y: -2, duration: 0.8), .fadeOut(withDuration: 0.8)]),
            .removeFromParent(),
        ]))
    }

    // MARK: Événements ponctuels

    func play(_ event: OtterEvent) {
        switch event {
        case .celebrate: celebrate()
        case .snapshot: snapshot()
        case .caught: caught()
        case .pomodoroDone: pomodoroDone()
        }
    }

    /// Capture d'écran : un vrai flash d'appareil photo, court et sec.
    private func snapshot() {
        let flash = SKSpriteNode(color: .white, size: size)
        flash.name = "fx"
        flash.position = center
        flash.zPosition = 10
        flash.alpha = 0
        addChild(flash)
        flash.run(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.05),
            .fadeOut(withDuration: 0.28),
            .removeFromParent(),
        ]))

        let camera = SKLabelNode(text: "📸")
        camera.name = "fx"
        camera.fontSize = 14
        camera.position = CGPoint(x: size.width * 0.5, y: size.height * 0.72)
        camera.setScale(0.4)
        addChild(camera)
        camera.run(.sequence([
            .group([.scale(to: 1, duration: 0.18), .moveBy(x: 0, y: 6, duration: 0.18)]),
            .wait(forDuration: 0.35),
            .fadeOut(withDuration: 0.25),
            .removeFromParent(),
        ]))
        hop()
    }

    /// Fichier déposé sur l'étagère : elle l'attrape au vol.
    private func caught() {
        let parcel = SKLabelNode(text: "📦")
        parcel.name = "fx"
        parcel.fontSize = 13
        parcel.position = CGPoint(x: size.width * 0.5, y: size.height * 1.05)
        addChild(parcel)

        let fall = SKAction.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.56), duration: 0.32)
        fall.timingMode = .easeIn
        parcel.run(.sequence([
            fall,
            .group([.scale(to: 0.6, duration: 0.18), .fadeOut(withDuration: 0.18)]),
            .removeFromParent(),
        ]))
        // Elle se baisse pour réceptionner, puis se redresse.
        otter?.run(.sequence([
            .wait(forDuration: 0.24),
            .moveBy(x: 0, y: -5, duration: 0.08),
            .moveBy(x: 0, y: 5, duration: 0.2),
        ]))
    }

    /// Session de travail bouclée : elle s'étire et souffle.
    private func pomodoroDone() {
        guard let otter else { return }
        otter.run(.sequence([
            .scaleX(to: 1.14, y: 0.92, duration: 0.22),
            .scaleX(to: 1.0, y: 1.0, duration: 0.30),
        ]))
        let mark = SKLabelNode(text: "✅")
        mark.name = "fx"
        mark.fontSize = 14
        mark.alpha = 0
        mark.position = CGPoint(x: size.width * 0.5, y: size.height * 0.74)
        addChild(mark)
        mark.run(.sequence([
            .group([.fadeIn(withDuration: 0.15), .moveBy(x: 0, y: 8, duration: 0.5)]),
            .wait(forDuration: 0.5),
            .fadeOut(withDuration: 0.35),
            .removeFromParent(),
        ]))
    }

    /// Approbation d'une action Claude Code : petite fête, elle lance un coquillage.
    private func celebrate() {
        wiggle()
        let shell = SKLabelNode(text: "🐚")
        shell.name = "fx"
        shell.fontSize = 14
        shell.position = CGPoint(x: size.width * 0.5, y: size.height * 0.55)
        addChild(shell)

        let up = SKAction.moveBy(x: 0, y: 22, duration: 0.4)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -22, duration: 0.4)
        down.timingMode = .easeIn
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.8)
        shell.run(.sequence([
            .group([.sequence([up, down]), spin]),
            .removeFromParent(),
        ]))
    }
}
