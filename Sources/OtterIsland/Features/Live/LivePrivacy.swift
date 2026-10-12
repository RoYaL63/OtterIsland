import AppKit
import ApplicationServices

/// Repère les secrets VISIBLES à l'écran (clés API, jetons, mots de passe en
/// clair) et renvoie leur position pour les recouvrir.
///
/// Passe par l'Accessibilité, pas par une lecture d'image : on demande à l'app
/// le texte affiché et sa position. Deux passes :
/// - le champ actif (celui où l'on tape), toutes les 0,25 s — c'est là qu'une
///   clé apparaît pendant qu'on la colle ;
/// - toute la fenêtre active, un relevé sur trois (0,75 s) — une clé affichée
///   dans une page (tableau de bord OpenAI, fichier .env ouvert…).
/// Un clic, un collage, Tab ou un changement d'app déclenchent un relevé
/// immédiat en plus (voir `LiveController.triggerSecretScan`).
///
/// Au-delà des motifs de clés connus, le planificateur (`SecretPlanner`)
/// ANTICIPE : un champ qui se déclare mot de passe ou secret est couvert dès
/// qu'il s'affiche, et une valeur sous un libellé « API key » l'est aussi. Le
/// bouton œil afficher / masquer n'est jamais recouvert.
///
/// Chrome, Edge, Brave, Arc et les apps Electron ne publient le contenu de
/// leurs pages qu'à la demande : on le leur demande (`AXManualAccessibility`),
/// une fois par processus. Sans ça, une clé tapée sur platform.openai.com
/// restait invisible pour le scanner.
///
/// Tout tourne sur une file d'arrière-plan : une page lourde ou une app figée
/// ne bloque jamais l'île ni le dessin.
enum SecretScanner {

    /// Processus à qui l'on a déjà demandé d'exposer leurs pages web. Lu et
    /// écrit uniquement depuis la file de scan (série).
    private static var webAccessibilityEnabled: Set<pid_t> = []

    /// Rectangles écran (repère AppKit) des secrets visibles.
    /// - Parameters:
    ///   - primaryHeight: hauteur de l'écran principal, pour convertir le repère
    ///     « haut-gauche » de l'Accessibilité (lue sur le thread principal).
    ///   - deep: parcourir aussi toute la fenêtre active.
    ///   - anticipate: couvrir d'avance les champs qui se déclarent mot de
    ///     passe ou secret, et les valeurs placées sous un libellé de clé.
    static func visibleSecretRects(primaryHeight: CGFloat, deep: Bool, anticipate: Bool = true) -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        // Pas de délai réglé sur l'élément système : il deviendrait le défaut
        // de TOUTE l'app (collage, verrouillage clavier…). Les délais courts
        // sont posés sur chaque élément interrogé.
        let system = AXUIElementCreateSystemWide()

        guard let app = AXScanNode.element(system, kAXFocusedApplicationAttribute) else { return [] }
        AXUIElementSetMessagingTimeout(app, 0.25)
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        if pid > 0, !webAccessibilityEnabled.contains(pid) {
            webAccessibilityEnabled.insert(pid)
            // Chromium et Electron : publie l'arbre des pages web. Sans effet
            // (et sans erreur gênante) sur les autres apps.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        var rects: [CGRect] = []
        if let focused = AXScanNode.element(app, kAXFocusedUIElementAttribute),
           let node = AXScanNode(element: focused, parent: nil, primaryHeight: primaryHeight, timeout: 0.25) {
            rects += SecretPlanner.planFocused(node, anticipate: anticipate)
        }
        if deep, let window = AXScanNode.element(app, kAXFocusedWindowAttribute),
           let node = AXScanNode(element: window, parent: nil, primaryHeight: primaryHeight, timeout: 0.1) {
            rects += SecretPlanner.planTree(root: node, anticipate: anticipate)
        }
        return Array(rects.prefix(60))
    }
}

/// Élément de l'interface lu par l'Accessibilité. Tous ses attributs sont
/// récupérés en UN aller-retour : c'est le coût qui compte sur une page lourde.
final class AXScanNode: ScanNode {
    let element: AXUIElement
    private let primaryHeight: CGFloat
    private let timeout: Float
    private var parentNode: AXScanNode?
    private var childElements: [AXUIElement] = []
    private var childNodes: [ScanNode]?

    let role: String
    let subrole: String
    let value: String?
    let descriptors: [String]
    let frame: CGRect?

    private static let attributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXChildrenAttribute,
        kAXPositionAttribute, kAXSizeAttribute,
        "AXPlaceholderValue", kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute,
        "AXDOMIdentifier", "AXDOMClassList",
    ] as CFArray

    init?(element: AXUIElement, parent: AXScanNode?, primaryHeight: CGFloat, timeout: Float) {
        self.element = element
        self.primaryHeight = primaryHeight
        self.timeout = timeout
        parentNode = parent
        AXUIElementSetMessagingTimeout(element, timeout)

        var valuesRef: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, Self.attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
              let values = valuesRef as? [AnyObject], values.count == 12
        else { return nil }

        role = values[0] as? String ?? ""
        subrole = values[1] as? String ?? ""
        value = values[2] as? String
        childElements = (values[3] as? [AXUIElement]) ?? []
        frame = Self.rect(position: values[4], size: values[5], primaryHeight: primaryHeight)
        var texts = [6, 7, 8, 9, 10].compactMap { values[$0] as? String }
        if let classes = values[11] as? [String] { texts.append(contentsOf: classes) }
        descriptors = texts.filter { !$0.isEmpty }
    }

    var parent: ScanNode? {
        if let parentNode { return parentNode }
        guard let parentElement = Self.element(element, kAXParentAttribute) else { return nil }
        parentNode = AXScanNode(element: parentElement, parent: nil, primaryHeight: primaryHeight, timeout: timeout)
        return parentNode
    }

    var children: [ScanNode] {
        if let childNodes { return childNodes }
        let nodes = childElements.prefix(300).compactMap {
            AXScanNode(element: $0, parent: self, primaryHeight: primaryHeight, timeout: timeout) as ScanNode?
        }
        childNodes = nodes
        return nodes
    }

    func isSame(as other: ScanNode) -> Bool {
        guard let other = other as? AXScanNode else { return false }
        return CFEqual(element, other.element)
    }

    func textBounds(location: Int, length: Int) -> CGRect? {
        var range = CFRange(location: location, length: length)
        guard let param = AXValueCreate(.cfRange, &range) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return ScreenGeometry.cocoaRect(fromTopLeft: rect, primaryHeight: primaryHeight)
    }

    /// Le texte À L'ÉCRAN seulement : un terminal garde des milliers de lignes
    /// d'historique, inutile de toutes les relire plusieurs fois par seconde.
    func visibleText() -> (text: String, offset: Int)? {
        var rangeRef: CFTypeRef?
        var range = CFRange(location: 0, length: 0)
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
        } else if let count = Self.int(element, kAXNumberOfCharactersAttribute), count <= 20_000 {
            range = CFRange(location: 0, length: count)
        }
        if range.length > 0, range.length <= 60_000, let param = AXValueCreate(.cfRange, &range) {
            var stringRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, param, &stringRef) == .success,
               let string = stringRef as? String {
                return (string, range.location)
            }
        }
        // Repli : la valeur complète (champs web, qui n'exposent pas toujours
        // la plage visible), découpée à 20 000 caractères.
        guard let value else { return nil }
        let ns = value as NSString
        let length = min(ns.length, 20_000)
        let start = range.length > 0 ? min(range.location, ns.length) : 0
        let safe = NSRange(location: start, length: min(length, ns.length - start))
        return (ns.substring(with: safe), safe.location)
    }

    // MARK: Aides

    /// Cadre écran à partir des valeurs AXPosition / AXSize déjà lues.
    private static func rect(position: AnyObject, size: AnyObject, primaryHeight: CGFloat) -> CGRect? {
        let posRef = position as CFTypeRef, sizeRef = size as CFTypeRef
        guard CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0
        else { return nil }
        return ScreenGeometry.cocoaRect(fromTopLeft: CGRect(origin: origin, size: extent), primaryHeight: primaryHeight)
    }

    static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, name as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func int(_ element: AXUIElement, _ name: String) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }
}

/// Fenêtres des applications à cacher pendant le Live (gestionnaire de mots de
/// passe, Messages…). La liste des fenêtres et leurs positions sont publiques
/// (CGWindowList) : pas besoin de l'autorisation d'enregistrement d'écran.
enum AppMasker {

    @MainActor
    static func windowRects(for bundleIDs: Set<String>) -> [CGRect] {
        guard !bundleIDs.isEmpty else { return [] }
        let pids = Set(NSWorkspace.shared.runningApplications
            .filter { bundleIDs.contains($0.bundleIdentifier ?? "") && !$0.isHidden }
            .map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var rects: [CGRect] = []
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 40, bounds.height > 40
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            rects.append(ScreenGeometry.cocoaRect(fromTopLeft: bounds))
        }
        return rects
    }
}

/// Conversions entre le repère « haut-gauche » (CGWindowList, Accessibilité)
/// et le repère AppKit « bas-gauche », tous deux ancrés sur l'écran principal.
enum ScreenGeometry {
    @MainActor
    static func cocoaRect(fromTopLeft rect: CGRect) -> CGRect {
        cocoaRect(fromTopLeft: rect, primaryHeight: primaryHeight)
    }

    static func cocoaRect(fromTopLeft rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    @MainActor
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
}
