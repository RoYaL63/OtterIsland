import AppKit

/// Quels écrans affichent une app en plein écran (film, présentation, jeu) ?
///
/// Une app en plein écran possède une fenêtre qui couvre l'écran ENTIER, barre
/// des menus comprise. Une fenêtre agrandie normalement s'arrête sous la barre
/// des menus : elle ne couvre jamais l'écran en entier. La liste des fenêtres
/// et leurs cadres sont publics (CGWindowList) : aucune autorisation requise,
/// comme pour `AppMasker`.
enum FullscreenDetector {

    /// Une fenêtre couvre-t-elle l'écran en entier ? Marge de 2 pt : certaines
    /// apps rognent ou débordent d'un point.
    static func covers(_ window: CGRect, screen: CGRect) -> Bool {
        window.insetBy(dx: -2, dy: -2).contains(screen)
    }

    /// Les fenêtres à prendre en compte : de premier niveau (calque 0), visibles,
    /// et pas les nôtres (le panneau de l'île couvre tout l'écran pendant le Live).
    @MainActor
    static func windowRects(excludingPID excluded: pid_t = getpid()) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var rects: [CGRect] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != excluded,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width > 200, bounds.height > 200
            else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            rects.append(ScreenGeometry.cocoaRect(fromTopLeft: bounds))
        }
        return rects
    }

    /// Identifiants (`ScreenIdentifier.stableID`) des écrans qui montrent une
    /// app en plein écran.
    @MainActor
    static func screensInFullscreen(excludingPID excluded: pid_t = getpid()) -> Set<String> {
        let windows = windowRects(excludingPID: excluded)
        guard !windows.isEmpty else { return [] }
        var result = Set<String>()
        for screen in NSScreen.screens {
            if windows.contains(where: { covers($0, screen: screen.frame) }) {
                result.insert(ScreenIdentifier.stableID(for: screen))
            }
        }
        return result
    }
}
