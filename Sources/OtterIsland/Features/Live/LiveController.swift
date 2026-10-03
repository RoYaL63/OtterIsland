import AppKit
import Carbon.HIToolbox
import Combine

/// Le mode Live (présentateur) : dessins éphémères, effets de curseur,
/// projecteur, touches affichées, masquage des secrets.
///
/// Rien ne tourne tant que le Live est éteint : ni fenêtre, ni moniteur
/// d'événements, ni minuterie. Allumé, il réagit aux événements (souris,
/// clavier) plutôt que d'interroger en boucle ; les seules minuteries sont le
/// masquage (2 fois/s, s'il est actif), la lecture de la touche de dessin
/// (15 fois/s, une simple lecture de drapeau) et l'animation de la traînée
/// de curseur, qui s'arrête dès que la souris est immobile.
@MainActor
final class LiveController: ObservableObject {

    @Published private(set) var isActive = false
    /// Outil du mode stylo. nil = la souris clique normalement.
    @Published private(set) var tool: LiveTool?
    @Published var cursorEffectOn = true
    @Published var spotlightOn = false
    @Published var keysOn = true
    @Published var maskingOn = true
    @Published private(set) var hasDrawings = false
    /// Le raccourci global ⌃⌥L a-t-il pu être enregistré ?
    @Published private(set) var toggleHotKeyFailed = false
    /// Raccourcis ⌃⌥ que macOS a refusés : la combinaison est déjà prise par
    /// une autre app (gestionnaire de fenêtres, lanceur…). Affichés comme tels
    /// dans la barre et le panneau, au lieu d'échouer en silence.
    @Published private(set) var failedShortcuts: Set<String> = []

    let style: LiveStyle
    let keystrokes = KeystrokeHUD()
    private let settings: OtterSettings

    private var overlays: [LiveOverlayWindow] = []
    private var monitors: [Any] = []
    private var liveHotKeys: [HotKey] = []
    /// Scan des secrets : en arrière-plan, un seul à la fois.
    private let scanQueue = DispatchQueue(label: "otterisland.live.secrets", qos: .userInitiated)
    private var scanInFlight = false
    private var scanTick = 0
    /// Secrets du champ actif (remplacés à chaque scan) et de la fenêtre
    /// entière (remplacés seulement par les scans complets) : les deux
    /// restent affichés, sinon une clé trouvée dans la page réapparaissait
    /// une demi-seconde sur deux.
    private var focusedSecretRects: [CGRect] = []
    private var deepSecretRects: [CGRect] = []
    /// Dernières préférences vues, pour ne réagir qu'aux changements utiles.
    private var lastPrefs: LivePreferences
    private var toggleHotKey: HotKey?
    private var maskTimer: Timer?
    private var modifierTimer: Timer?
    private var trailTimer: Timer?
    private var modifierHeld = false
    private var activeCanvas: LiveCanvasView?
    private var trail: [LiveCanvasView.TrailPoint] = []
    private var trailCanvas: LiveCanvasView?
    /// Dernier mouvement (position, instant), pour la vitesse des étincelles
    /// et leur arrêt quand la souris s'immobilise.
    private var lastMove: (point: CGPoint, time: CFTimeInterval)?
    private var cancellables = Set<AnyCancellable>()
    private lazy var customizeWindow = LiveCustomizeWindowController(live: self)

    init(settings: OtterSettings, style: LiveStyle = LiveStyle()) {
        self.settings = settings
        self.style = style
        self.lastPrefs = style.prefs
        keysOn = style.prefs.showKeys
        installToggleHotKey()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isActive else { return }
                    self.rebuildOverlays()
                }
            }
            .store(in: &cancellables)

        // Un changement d'effet de curseur ou de masquage s'applique à chaud.
        style.$prefs
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.preferencesChanged() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Activation

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        isActive = true
        keysOn = style.prefs.showKeys
        rebuildOverlays()
        installMonitors()
        installLiveHotKeys()
        startModifierWatch()
        updateMaskTimer()
        if style.prefs.focusDuringLive {
            FocusMode.trigger(settings.pomodoroFocusShortcutOn)
        }
    }

    /// - Parameter waitForFocus: à la fermeture de l'app, le raccourci qui
    ///   coupe la Concentration doit être lancé AVANT que le processus meure.
    func stop(waitForFocus: Bool = false) {
        guard isActive else { return }
        isActive = false
        activeCanvas = nil
        modifierHeld = false
        setTool(nil)
        overlays.forEach { $0.canvas.clearAll(); $0.orderOut(nil) }
        overlays = []
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        liveHotKeys = []
        focusedSecretRects = []
        deepSecretRects = []
        maskTimer?.invalidate(); maskTimer = nil
        modifierTimer?.invalidate(); modifierTimer = nil
        trailTimer?.invalidate(); trailTimer = nil
        trail = []
        trailCanvas = nil
        lastMove = nil
        keystrokes.hide()
        hasDrawings = false
        spotlightOn = false
        if style.prefs.focusDuringLive {
            if waitForFocus {
                FocusMode.runAndWait(settings.pomodoroFocusShortcutOff)
            } else {
                FocusMode.trigger(settings.pomodoroFocusShortcutOff)
            }
        }
    }

    // MARK: - Outils

    /// Choisir l'outil déjà actif le désactive : la souris redevient normale.
    func select(_ newTool: LiveTool) {
        setTool(tool == newTool ? nil : newTool)
    }

    /// Le Live ne CAPTURE aucun raccourci des apps (⌘Z, ⌘V, Échap…) : ils
    /// continuent de marcher partout. Échap est seulement OBSERVÉ (voir
    /// `keyPressed`) pour sortir du mode stylo ; l'annulation passe par ⌃⌥Z.
    func setTool(_ newTool: LiveTool?) {
        tool = newTool
        updateMouseCapture()
    }

    /// Échap : efface tout, puis rend la souris.
    func escape() {
        clearAll()
        setTool(nil)
    }

    func undo() {
        let latest = overlays.compactMap { o in o.canvas.latestShape.map { (o.canvas, $0) } }
            .max { $0.1.createdAt < $1.1.createdAt }
        if let latest { latest.0.remove(latest.1) }
        refreshHasDrawings()
    }

    func clearAll() {
        overlays.forEach { $0.canvas.clearAll() }
        refreshHasDrawings()
    }

    func toggleSpotlight() {
        spotlightOn.toggle()
        if !spotlightOn { overlays.forEach { $0.canvas.renderSpotlight(at: nil, radius: 0, darkness: 0) } }
        else { updateCursorEffects(at: NSEvent.mouseLocation) }
    }

    func toggleCursorEffect() {
        cursorEffectOn.toggle()
        if !cursorEffectOn { overlays.forEach { $0.canvas.hideCursorEffects() }; trail = [] }
    }

    func toggleKeys() {
        keysOn.toggle()
        if !keysOn { keystrokes.hide() }
    }

    func toggleMasking() {
        maskingOn.toggle()
        updateMaskTimer()
    }

    func selectColor(_ hex: String) {
        style.prefs.colorHex = hex
    }

    /// La loupe de macOS (Accessibilité › Zoom), déclenchée par son raccourci
    /// ⌥⌘8. On ne réinvente pas une loupe qui capturerait l'écran en continu.
    func toggleSystemZoom() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let key = CGKeyCode(kVK_ANSI_8)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = [.maskCommand, .maskAlternate]
        up?.flags = [.maskCommand, .maskAlternate]
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func openCustomization() {
        customizeWindow.show()
    }

    // MARK: - Raccourcis

    /// Raccourcis ⌃⌥ + lettre, actifs seulement pendant le Live. Affichés dans
    /// la barre de l'island et le panneau de personnalisation.
    struct Shortcut: Identifiable, Sendable {
        let id: String
        let letter: String
        let title: String
        let keyCode: Int
    }

    static let shortcuts: [Shortcut] = [
        Shortcut(id: "live", letter: "L", title: "Démarrer / arrêter le Live", keyCode: kVK_ANSI_L),
        Shortcut(id: "pen", letter: "P", title: "Stylo", keyCode: kVK_ANSI_P),
        Shortcut(id: "arrow", letter: "F", title: "Flèche", keyCode: kVK_ANSI_F),
        Shortcut(id: "rectangle", letter: "R", title: "Rectangle", keyCode: kVK_ANSI_R),
        Shortcut(id: "ellipse", letter: "O", title: "Cercle", keyCode: kVK_ANSI_O),
        Shortcut(id: "marker", letter: "S", title: "Surligneur", keyCode: kVK_ANSI_S),
        Shortcut(id: "laser", letter: "T", title: "Laser", keyCode: kVK_ANSI_T),
        Shortcut(id: "effect", letter: "H", title: "Effet de curseur", keyCode: kVK_ANSI_H),
        Shortcut(id: "spotlight", letter: "B", title: "Projecteur", keyCode: kVK_ANSI_B),
        Shortcut(id: "keys", letter: "K", title: "Touches affichées", keyCode: kVK_ANSI_K),
        Shortcut(id: "mask", letter: "M", title: "Masquage", keyCode: kVK_ANSI_M),
        Shortcut(id: "undo", letter: "Z", title: "Annuler le dernier dessin", keyCode: kVK_ANSI_Z),
        Shortcut(id: "clear", letter: "X", title: "Tout effacer", keyCode: kVK_ANSI_X),
        Shortcut(id: "zoom", letter: "8", title: "Loupe macOS (⌥⌘8)", keyCode: kVK_ANSI_8),
    ]

    static func letter(for id: String) -> String {
        shortcuts.first { $0.id == id }?.letter ?? ""
    }

    private static let liveModifiers = UInt32(controlKey | optionKey)

    private func installToggleHotKey() {
        let hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: Self.liveModifiers) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
        toggleHotKey = hotKey
        toggleHotKeyFailed = !hotKey.isRegistered
    }

    private func installLiveHotKeys() {
        // Le raccourci du presse-papier passe avant tout : s'il tombe sur une
        // combinaison ⌃⌥, le Live renonce à la sienne.
        let clipboardTaken = settings.clipboardHotKeyModifiers == Int(controlKey | optionKey)
            ? settings.clipboardHotKeyCode : -1
        var failed: Set<String> = []
        var installed: [HotKey] = []
        for shortcut in Self.shortcuts where shortcut.id != "live" && shortcut.id != "zoom" {
            guard shortcut.keyCode != clipboardTaken else {
                failed.insert(shortcut.id)
                continue
            }
            let hotKey = HotKey(keyCode: UInt32(shortcut.keyCode), modifiers: Self.liveModifiers) { [weak self] in
                MainActor.assumeIsolated { self?.perform(shortcut.id) }
            }
            if hotKey.isRegistered { installed.append(hotKey) } else { failed.insert(shortcut.id) }
        }
        liveHotKeys = installed
        failedShortcuts = failed
    }

    func perform(_ id: String) {
        if let tool = LiveTool(rawValue: id) { select(tool); return }
        switch id {
        case "effect": toggleCursorEffect()
        case "spotlight": toggleSpotlight()
        case "keys": toggleKeys()
        case "mask": toggleMasking()
        case "undo": undo()
        case "clear": clearAll()
        case "zoom": toggleSystemZoom()
        case "live": toggle()
        default: break
        }
    }

    // MARK: - Fenêtres

    private func rebuildOverlays() {
        activeCanvas = nil
        modifierHeld = false
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let window = LiveOverlayWindow(screen: screen)
            window.canvas.onMouseDown = { [weak self] canvas, point, event in
                MainActor.assumeIsolated { self?.canvasMouseDown(canvas, point, event) }
            }
            window.canvas.onMouseDragged = { [weak self] canvas, point in
                MainActor.assumeIsolated { self?.canvasMouseDragged(canvas, point) }
            }
            window.canvas.onMouseUp = { [weak self] canvas, point in
                MainActor.assumeIsolated { self?.canvasMouseUp(canvas, point) }
            }
            window.orderFrontRegardless()
            return window
        }
        updateMouseCapture()
        hasDrawings = false
    }

    /// Le canevas n'attrape la souris que pour dessiner : en mode stylo, ou
    /// pendant que la touche de dessin est maintenue.
    private func updateMouseCapture() {
        let capture = isActive && (tool != nil || modifierHeld)
        for overlay in overlays where overlay.ignoresMouseEvents == capture {
            overlay.ignoresMouseEvents = !capture
        }
        if capture { NSCursor.crosshair.set() } else if isActive { NSCursor.arrow.set() }
    }

    private func startModifierWatch() {
        modifierTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkModifier() }
        }
        RunLoop.main.add(t, forMode: .common)
        modifierTimer = t
    }

    private func checkModifier() {
        guard let flag = style.prefs.drawModifier.flag else {
            if modifierHeld { modifierHeld = false; updateMouseCapture() }
            return
        }
        let current = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // La touche SEULE : ⌃⌥ + lettre (nos raccourcis) ou ⌃⌘… ne doivent pas
        // transformer la souris en stylo.
        let held = current == flag
        guard held != modifierHeld else { return }
        // Ne pas couper un trait en cours si la touche est relâchée en route.
        if !held, activeCanvas != nil { return }
        modifierHeld = held
        updateMouseCapture()
    }

    // MARK: - Dessin

    private func canvasMouseDown(_ canvas: LiveCanvasView, _ point: CGPoint, _ event: NSEvent) {
        if style.prefs.clickRipples {
            canvas.spawnClick(Self.clickKind(event), at: point, color: style.effectColor)
        }
        guard event.type == .leftMouseDown else { return }
        // En mode stylo, cliquer sur un dessin l'efface.
        if tool != nil, tool != .laser, let shape = canvas.shape(at: point) {
            canvas.remove(shape)
            refreshHasDrawings()
            return
        }
        let p = style.prefs
        let strokeStyle = LiveCanvasView.StrokeStyle(
            color: style.color, width: p.strokeWidth, glow: p.glow,
            fadeSeconds: p.fadeSeconds, straighten: p.straightenShapes
        )
        canvas.beginStroke(at: point, tool: tool ?? .pen, style: strokeStyle)
        activeCanvas = canvas
    }

    private func canvasMouseDragged(_ canvas: LiveCanvasView, _ point: CGPoint) {
        guard activeCanvas === canvas else { return }
        canvas.continueStroke(to: point)
    }

    private func canvasMouseUp(_ canvas: LiveCanvasView, _ point: CGPoint) {
        guard activeCanvas === canvas else { return }
        canvas.continueStroke(to: point)
        canvas.endStroke { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHasDrawings() }
        }
        activeCanvas = nil
        refreshHasDrawings()
        checkModifier()
    }

    private func refreshHasDrawings() {
        hasDrawings = overlays.contains { !$0.canvas.shapes.isEmpty }
    }

    // MARK: - Souris et clavier

    private func installMonitors() {
        let mouseMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let clickMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCursorEffects(at: NSEvent.mouseLocation) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.updateCursorEffects(at: NSEvent.mouseLocation) }
            return event
        }) { monitors.append(local) }

        // Ondes au clic dans les AUTRES apps (les clics sur le canevas les
        // produisent eux-mêmes, voir canvasMouseDown).
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: clickMask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.globalClick(event) }
        }) { monitors.append(clicks) }

        // Touches affichées : demande l'autorisation Accessibilité (déjà
        // utilisée par le collage automatique). Sans elle, macOS ne transmet
        // simplement rien.
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.keyPressed(event) }
        }) { monitors.append(keys) }
        // Quand OtterIsland est au premier plan (panneau Personnaliser), les
        // frappes ne passent pas par le moniteur global.
        if let localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.keyPressed(event) }
            return event
        }) { monitors.append(localKeys) }
    }

    private func globalClick(_ event: NSEvent) {
        guard style.prefs.clickRipples, let overlay = overlay(containing: NSEvent.mouseLocation) else { return }
        overlay.canvas.spawnClick(Self.clickKind(event), at: overlay.local(NSEvent.mouseLocation), color: style.effectColor)
    }

    private static func clickKind(_ event: NSEvent) -> LiveCanvasView.ClickKind {
        if event.type == .rightMouseDown { return .right }
        return event.clickCount >= 2 ? .double : .left
    }

    private func keyPressed(_ event: NSEvent) {
        // Échap observé (pas intercepté) : l'app au premier plan le reçoit
        // aussi, mais le mode stylo s'arrête et les dessins s'effacent.
        if Int(event.keyCode) == kVK_Escape, tool != nil,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            escape()
        }
        guard keysOn, let labels = KeystrokeHUD.labels(for: event) else { return }
        keystrokes.show(labels, position: style.prefs.keysPosition, scale: style.prefs.keysScale)
    }

    private func overlay(containing point: NSPoint) -> LiveOverlayWindow? {
        overlays.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func updateCursorEffects(at location: NSPoint) {
        guard isActive, let overlay = overlay(containing: location) else { return }
        let point = overlay.local(location)
        let canvas = overlay.canvas

        if spotlightOn {
            for other in overlays {
                other.canvas.renderSpotlight(
                    at: other === overlay ? point : nil,
                    radius: style.prefs.spotlightRadius,
                    darkness: style.prefs.spotlightDarkness
                )
            }
        }

        guard cursorEffectOn else { return }
        let p = style.prefs
        switch p.cursorEffect {
        case .none:
            canvas.hideCursorEffects()
        case .halo:
            switchEffectCanvas(to: canvas)
            canvas.renderRing(at: point, color: style.effectColor, size: p.cursorEffectSize)
        case .meteor:
            switchEffectCanvas(to: canvas)
            let now = CACurrentMediaTime()
            trail.append(.init(point: point, time: now))
            renderTrail(now: now)
            startTrailTimer()
        case .sparkles:
            switchEffectCanvas(to: canvas)
            let now = CACurrentMediaTime()
            var speed: CGFloat = 0
            if let last = lastMove, now > last.time {
                speed = hypot(point.x - last.point.x, point.y - last.point.y) / CGFloat(now - last.time)
            }
            lastMove = (point, now)
            canvas.emitSparks(at: point, color: style.effectColor, size: p.cursorEffectSize, speed: speed)
            startTrailTimer()
        case .dots:
            switchEffectCanvas(to: canvas)
            canvas.dropDots(at: point, color: style.effectColor, size: p.cursorEffectSize)
        }
    }

    /// L'effet suit le curseur d'un écran à l'autre : on éteint l'ancien.
    private func switchEffectCanvas(to canvas: LiveCanvasView) {
        guard trailCanvas !== canvas else { return }
        trailCanvas?.hideCursorEffects()
        trailCanvas = canvas
        trail = []
        lastMove = nil
    }

    /// La traînée doit se résorber APRÈS l'arrêt de la souris : une minuterie
    /// la fait vivre, et s'arrête d'elle-même quand il n'en reste rien.
    private func startTrailTimer() {
        guard trailTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderTrail(now: CACurrentMediaTime()) }
        }
        RunLoop.main.add(t, forMode: .common)
        trailTimer = t
    }

    /// Une image de l'effet en cours, tant qu'il reste quelque chose à faire
    /// vivre : la comète se résorbe, les étincelles s'arrêtent 60 ms après le
    /// dernier mouvement. Puis la minuterie s'arrête d'elle-même.
    private func renderTrail(now: CFTimeInterval) {
        let p = style.prefs
        guard let canvas = trailCanvas else { stopTrailTimer(); return }
        switch p.cursorEffect {
        case .meteor:
            trail.removeAll { now - $0.time > 0.3 }
            if trail.count > 90 { trail.removeFirst(trail.count - 90) }
            canvas.renderComet(trail: trail, color: style.effectColor, size: p.cursorEffectSize)
            if trail.isEmpty { stopTrailTimer() }
        case .sparkles:
            if let last = lastMove, now - last.time < 0.06 { return }
            canvas.stopSparks()
            lastMove = nil
            stopTrailTimer()
        default:
            stopTrailTimer()
        }
    }

    private func stopTrailTimer() {
        trailTimer?.invalidate()
        trailTimer = nil
    }

    private func preferencesChanged() {
        let old = lastPrefs
        let new = style.prefs
        lastPrefs = new
        guard isActive else { return }
        if old.cursorEffect != new.cursorEffect {
            overlays.forEach { $0.canvas.hideCursorEffects() }
            trail = []
        }
        if old.maskSecrets != new.maskSecrets || old.maskApps != new.maskApps || old.maskedBundleIDs != new.maskedBundleIDs {
            updateMaskTimer()
        }
        if spotlightOn, old.spotlightRadius != new.spotlightRadius || old.spotlightDarkness != new.spotlightDarkness {
            updateCursorEffects(at: NSEvent.mouseLocation)
        }
    }

    // MARK: - Masquage

    private func updateMaskTimer() {
        let p = style.prefs
        let needed = isActive && maskingOn && (p.maskSecrets || p.maskApps)
        if !needed {
            maskTimer?.invalidate(); maskTimer = nil
            focusedSecretRects = []
            deepSecretRects = []
            overlays.forEach { $0.canvas.renderMasks([]) }
            return
        }
        guard maskTimer == nil else { refreshMasks(); return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMasks() }
        }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        maskTimer = t
        refreshMasks()
    }

    private func refreshMasks() {
        let p = style.prefs
        if p.maskSecrets {
            startSecretScan()
        } else {
            focusedSecretRects = []
            deepSecretRects = []
        }
        renderAllMasks()
    }

    /// Le scan des secrets part en arrière-plan ; la fenêtre active entière
    /// n'est parcourue qu'un relevé sur deux (une fois par seconde).
    private func startSecretScan() {
        guard !scanInFlight else { return }
        scanInFlight = true
        scanTick += 1
        let deep = scanTick % 2 == 0
        let height = ScreenGeometry.primaryHeight
        scanQueue.async { [weak self] in
            let rects = SecretScanner.visibleSecretRects(primaryHeight: height, deep: deep)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.scanInFlight = false
                    guard self.isActive, self.maskingOn, self.style.prefs.maskSecrets else { return }
                    if deep {
                        // Le scan complet couvre aussi le champ actif.
                        self.deepSecretRects = rects
                        self.focusedSecretRects = []
                    } else {
                        self.focusedSecretRects = rects
                    }
                    self.renderAllMasks()
                }
            }
        }
    }

    private func renderAllMasks() {
        let p = style.prefs
        var masks: [(CGRect, LiveCanvasView.MaskKind)] = []
        if p.maskApps {
            masks += AppMasker.windowRects(for: Set(p.maskedBundleIDs)).map { ($0, LiveCanvasView.MaskKind.app) }
        }
        masks += (focusedSecretRects + deepSecretRects).map { ($0, LiveCanvasView.MaskKind.secret) }
        for overlay in overlays {
            let local = masks.compactMap { rect, kind -> (CGRect, LiveCanvasView.MaskKind)? in
                let clipped = rect.intersection(overlay.frame)
                guard !clipped.isNull, !clipped.isEmpty else { return nil }
                return (clipped.offsetBy(dx: -overlay.frame.minX, dy: -overlay.frame.minY), kind)
            }
            overlay.canvas.renderMasks(local)
        }
    }
}
