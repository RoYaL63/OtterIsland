import AppKit
import ApplicationServices

/// Repère les secrets VISIBLES à l'écran (clés API, jetons, mots de passe en
/// clair) et renvoie leur position pour les recouvrir.
///
/// Passe par l'Accessibilité, pas par une lecture d'image : on demande à l'app
/// le texte affiché et sa position. Deux passes :
/// - le champ actif (celui où l'on tape), à chaque relevé — c'est là qu'une
///   clé apparaît pendant qu'on la colle ;
/// - toute la fenêtre active, une fois sur deux — une clé affichée dans une
///   page (tableau de bord OpenAI, fichier .env ouvert…).
///
/// Chrome, Edge, Brave, Arc et les apps Electron ne publient le contenu de
/// leurs pages qu'à la demande : on le leur demande (`AXManualAccessibility`),
/// une fois par processus. Sans ça, une clé tapée sur platform.openai.com
/// restait invisible pour le scanner.
///
/// Tout tourne sur une file d'arrière-plan : une page lourde ou une app figée
/// ne bloque jamais l'île ni le dessin.
enum SecretScanner {

    /// Motifs de clés connues. Le groupe 1, quand il existe, est la seule
    /// partie à masquer (la valeur, pas le nom de la variable).
    private static let patterns: [NSRegularExpression] = [
        #"sk-(?:proj-|ant-|svcacct-|admin-)?[A-Za-z0-9_\-]{16,}"#, // OpenAI, Anthropic
        #"(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{16,}"#,       // Stripe
        #"gh[pousr]_[A-Za-z0-9]{30,}"#,                         // GitHub
        #"github_pat_[A-Za-z0-9_]{40,}"#,
        #"AKIA[0-9A-Z]{16}"#,                                   // AWS
        #"AIza[0-9A-Za-z_\-]{35}"#,                             // Google
        #"xox[abposr]-[A-Za-z0-9\-]{10,}"#,                     // Slack
        #"pat[A-Za-z0-9]{14}\.[a-f0-9]{40,}"#,                  // Airtable
        #"(?:secret_|ntn_)[A-Za-z0-9]{30,}"#,                   // Notion
        #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}"#, // JWT (Supabase…)
        #"hooks\.slack\.com/services/[A-Za-z0-9/]{20,}"#,
        #"hook\.[a-z0-9]+\.make\.com/([A-Za-z0-9]{12,})"#,      // webhook Make
        #"(?i)\b(?:bearer|basic|token|digest)\s+([A-Za-z0-9._~+/=\-]{16,})"#,  // Authorization: Bearer …
        // En-têtes HTTP d'authentification : on garde le nom (et « Bearer »),
        // on masque la valeur.
        #"(?i)(?:authorization|proxy-authorization|x-api-key|api-key|x-auth-token|x-access-token|x-goog-api-key|x-make-apikey|apikey|cookie|set-cookie)["']?\s*[:=]\s*["']?(?:(?:bearer|basic|token|digest)\s+)?([^\s"',;]{8,})"#,
        // Paramètres d'URL : ?key=… &api_key=… &access_token=…
        #"(?i)[?&](?:key|api_?key|apikey|token|access_token|auth|secret|password|sig|signature)=([^&\s"'#]{8,})"#,
        // Identifiants dans une URL : https://user:motdepasse@hote
        #"(?i)[a-z][a-z0-9+.\-]*://[^\s/:@]+:([^\s/@]{4,})@"#,
        // Clés privées PEM
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)(?:password|passwd|pwd|secret|token|api[_\-]?key|access[_\-]?key|private[_\-]?key)["']?\s*[:=]\s*["']?([^\s"',;]{6,})"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Rôles qui portent du texte lisible.
    private static let textRoles: Set<String> = [
        "AXStaticText", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
    ]

    /// Processus à qui l'on a déjà demandé d'exposer leurs pages web. Lu et
    /// écrit uniquement depuis la file de scan (série).
    private static var webAccessibilityEnabled: Set<pid_t> = []

    /// Rectangles écran (repère AppKit) des secrets visibles.
    /// - Parameters:
    ///   - primaryHeight: hauteur de l'écran principal, pour convertir le repère
    ///     « haut-gauche » de l'Accessibilité (lue sur le thread principal).
    ///   - deep: parcourir aussi toute la fenêtre active.
    static func visibleSecretRects(primaryHeight: CGFloat, deep: Bool) -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        // Pas de délai réglé sur l'élément système : il deviendrait le défaut
        // de TOUTE l'app (collage, verrouillage clavier…). Les délais courts
        // sont posés sur chaque élément interrogé.
        let system = AXUIElementCreateSystemWide()

        guard let app = element(system, kAXFocusedApplicationAttribute) else { return [] }
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
        if let focused = element(app, kAXFocusedUIElementAttribute) {
            AXUIElementSetMessagingTimeout(focused, 0.25)
            rects += scanFocused(focused, primaryHeight: primaryHeight)
        }
        if deep, let window = element(app, kAXFocusedWindowAttribute) {
            rects += scanTree(window, primaryHeight: primaryHeight)
        }
        return Array(rects.prefix(60))
    }

    // MARK: Champ actif

    private static func scanFocused(_ element: AXUIElement, primaryHeight: CGFloat) -> [CGRect] {
        // Un vrai champ mot de passe affiche déjà des points : rien à faire.
        if stringAttribute(element, kAXRoleAttribute) == "AXSecureTextField" { return [] }
        guard let visible = visibleText(of: element), !visible.text.isEmpty else { return [] }
        return rects(in: visible.text, offset: visible.offset, element: element, primaryHeight: primaryHeight, fallbackToFrame: true)
    }

    /// Le texte À L'ÉCRAN seulement : un terminal garde des milliers de lignes
    /// d'historique, inutile de toutes les relire deux fois par seconde.
    private static func visibleText(of element: AXUIElement) -> (text: String, offset: Int)? {
        var rangeRef: CFTypeRef?
        var range = CFRange(location: 0, length: 0)
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            AXValueGetValue(rangeRef as! AXValue, .cfRange, &range)
        } else if let count = intAttribute(element, kAXNumberOfCharactersAttribute), count <= 20_000 {
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
        guard let value = stringAttribute(element, kAXValueAttribute) else { return nil }
        let ns = value as NSString
        let length = min(ns.length, 20_000)
        let start = range.length > 0 ? min(range.location, ns.length) : 0
        let safe = NSRange(location: start, length: min(length, ns.length - start))
        return (ns.substring(with: safe), safe.location)
    }

    // MARK: Fenêtre active

    /// Parcours en largeur de la fenêtre, limité à ce qui est À L'ÉCRAN : un
    /// sous-arbre dont le cadre ne touche pas la fenêtre (le bas d'une page de
    /// résultats, un onglet caché) n'est pas visité. Sans cet élagage, une page
    /// Google épuisait le budget dans son en-tête avant d'atteindre le bloc de
    /// code affiché. Un seul aller-retour par élément.
    private static func scanTree(_ root: AXUIElement, primaryHeight: CGFloat) -> [CGRect] {
        let windowFrame = frame(of: root, primaryHeight: primaryHeight, limitSize: false)
        var queue: [AXUIElement] = [root]
        var head = 0
        var rects: [CGRect] = []
        let attributes = [kAXRoleAttribute, kAXValueAttribute, kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute] as CFArray

        while head < queue.count, head < 2500, rects.count < 40 {
            let node = queue[head]
            head += 1
            AXUIElementSetMessagingTimeout(node, 0.1)
            var valuesRef: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(node, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &valuesRef) == .success,
                  let values = valuesRef as? [AnyObject], values.count == 5
            else { continue }

            // Élagage : hors de la fenêtre visible, on ne descend pas.
            if let windowFrame, let nodeFrame = rect(position: values[3], size: values[4], primaryHeight: primaryHeight),
               nodeFrame.width > 0, nodeFrame.height > 0, !nodeFrame.intersects(windowFrame) {
                continue
            }

            let role = values[0] as? String ?? ""
            if role == "AXSecureTextField" { continue }
            if textRoles.contains(role), let text = values[1] as? String, text.count >= 8 {
                let clipped = String(text.prefix(4000))
                rects += self.rects(in: clipped, offset: 0, element: node, primaryHeight: primaryHeight, fallbackToFrame: true)
            }
            if let children = values[2] as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(300))
            }
        }
        return rects
    }

    /// Cadre écran à partir des valeurs AXPosition / AXSize déjà lues.
    private static func rect(position: AnyObject, size: AnyObject, primaryHeight: CGFloat) -> CGRect? {
        let posRef = position as CFTypeRef, sizeRef = size as CFTypeRef
        guard CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &extent)
        else { return nil }
        return ScreenGeometry.cocoaRect(fromTopLeft: CGRect(origin: origin, size: extent), primaryHeight: primaryHeight)
    }

    // MARK: Correspondances

    private static func rects(in text: String, offset: Int, element: AXUIElement, primaryHeight: CGFloat, fallbackToFrame: Bool) -> [CGRect] {
        let ns = text as NSString
        var out: [CGRect] = []
        var usedFrame = false
        for regex in patterns {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1) : match.range
                if let rect = bounds(of: CFRange(location: range.location + offset, length: range.length), in: element, primaryHeight: primaryHeight) {
                    out.append(rect.insetBy(dx: -3, dy: -2))
                } else if fallbackToFrame, !usedFrame, let frame = frame(of: element, primaryHeight: primaryHeight) {
                    // L'app ne sait pas situer un caractère : on couvre tout
                    // l'élément. Moins élégant, mais rien ne fuit.
                    usedFrame = true
                    out.append(frame.insetBy(dx: -2, dy: -2))
                }
                if out.count >= 20 { return out }
            }
        }
        return out
    }

    private static func bounds(of range: CFRange, in element: AXUIElement, primaryHeight: CGFloat) -> CGRect? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return ScreenGeometry.cocoaRect(fromTopLeft: rect, primaryHeight: primaryHeight)
    }

    private static func frame(of element: AXUIElement, primaryHeight: CGFloat, limitSize: Bool = true) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        // Masquer tout un élément n'a de sens que pour une ligne ou un champ :
        // un bloc de 600 pt couvrirait la moitié de l'écran.
        if limitSize, size.width >= 4000 || size.height >= 600 { return nil }
        return ScreenGeometry.cocoaRect(fromTopLeft: CGRect(origin: origin, size: size), primaryHeight: primaryHeight)
    }

    // MARK: Attributs

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, name as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func intAttribute(_ element: AXUIElement, _ name: String) -> Int? {
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
