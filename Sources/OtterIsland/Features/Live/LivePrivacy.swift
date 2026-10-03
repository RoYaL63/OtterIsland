import AppKit
import ApplicationServices

/// Repère les secrets VISIBLES dans le champ de texte actif (éditeur, terminal,
/// notes…) et renvoie leur position à l'écran pour les recouvrir.
///
/// Passe par l'Accessibilité, pas par une lecture d'image : on demande à l'app
/// le texte affiché et la position de chaque caractère. C'est précis et peu
/// coûteux — une poignée d'appels deux fois par seconde — mais ça ne voit que
/// ce que l'app expose. Les apps natives le font bien ; Chrome et les apps
/// Electron, partiellement. D'où le masquage par application, complémentaire.
enum SecretScanner {

    /// Motifs de clés connues. Le groupe 1, quand il existe, est la seule
    /// partie à masquer (la valeur, pas le nom de la variable).
    private static let patterns: [NSRegularExpression] = [
        #"sk-(?:proj-|ant-)?[A-Za-z0-9_\-]{20,}"#,             // OpenAI, Anthropic
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
        #"(?i)bearer\s+([A-Za-z0-9._\-]{20,})"#,
        #"(?i)(?:password|passwd|pwd|secret|token|api[_\-]?key|access[_\-]?key|private[_\-]?key)["']?\s*[:=]\s*["']?([^\s"',;]{6,})"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// Rectangles écran (repère AppKit) des secrets visibles dans l'élément actif.
    static func visibleSecretRects() -> [CGRect] {
        guard AXIsProcessTrusted() else { return [] }
        let system = AXUIElementCreateSystemWide()
        // Une app figée ne doit pas figer l'île : 0,2 s au lieu des ~6 s par
        // défaut de l'Accessibilité, sur le thread principal.
        AXUIElementSetMessagingTimeout(system, 0.2)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return [] }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.2)

        // Un vrai champ mot de passe affiche déjà des points : rien à faire.
        if stringAttribute(element, kAXRoleAttribute) == "AXSecureTextField" { return [] }

        guard let visible = visibleText(of: element), !visible.text.isEmpty else { return [] }
        let text = visible.text, offset = visible.offset
        let ns = text as NSString
        var rects: [CGRect] = []
        for regex in patterns {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let range = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1) : match.range
                if let rect = bounds(of: CFRange(location: range.location + offset, length: range.length), in: element) {
                    rects.append(rect.insetBy(dx: -3, dy: -2))
                }
                if rects.count >= 40 { return rects }
            }
        }
        return rects
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
        } else {
            return nil
        }
        guard range.length > 0, range.length <= 60_000 else { return nil }

        guard let param = AXValueCreate(.cfRange, &range) else { return nil }
        var stringRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, param, &stringRef) == .success,
           let string = stringRef as? String {
            return (string, range.location)
        }
        // Repli : la valeur complète, découpée à la plage visible.
        guard let value = stringAttribute(element, kAXValueAttribute) else { return nil }
        let ns = value as NSString
        let safe = NSIntersectionRange(NSRange(location: range.location, length: range.length), NSRange(location: 0, length: ns.length))
        return (ns.substring(with: safe), safe.location)
    }

    private static func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var r = range
        guard let param = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, param, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return ScreenGeometry.cocoaRect(fromTopLeft: rect)
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
    static func cocoaRect(fromTopLeft rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
