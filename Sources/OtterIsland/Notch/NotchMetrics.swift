import AppKit

/// Géométrie de l'encoche pour un écran donné. Coordonnées en repère écran
/// (origine en bas à gauche, comme AppKit).
struct NotchMetrics {
    let screen: NSScreen
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasRealNotch: Bool

    /// Rectangle de l'encoche, calé en haut au centre de l'écran.
    var notchRect: CGRect {
        CGRect(
            x: screenFrame.midX - notchSize.width / 2,
            y: screenFrame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
    }

    /// Largeur de l'onglet 🦦 qui remplace l'encoche sur un écran qui n'en a pas.
    static let handleWidth: CGFloat = 44

    static func current(for screen: NSScreen, widthOffset: CGFloat = 0) -> NotchMetrics {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        // Sur un Mac à encoche, les zones auxiliaires bordent le notch.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let computed = frame.width - left.width - right.width
            if computed > 0 {
                return NotchMetrics(
                    screen: screen,
                    screenFrame: frame,
                    notchSize: CGSize(
                        width: max(120, computed + widthOffset),
                        height: topInset > 0 ? topInset : 32
                    ),
                    hasRealNotch: true
                )
            }
        }

        // Pas d'encoche : plutôt qu'un faux bloc noir de 200 pt qui masquait le
        // milieu de la barre de menus, un petit onglet 🦦 de la hauteur de la
        // barre. Il sert de poignée : survol ou clic ouvrent l'île.
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        return NotchMetrics(
            screen: screen,
            screenFrame: frame,
            notchSize: CGSize(width: handleWidth, height: menuBar >= 20 ? menuBar : 24),
            hasRealNotch: false
        )
    }

    /// Écran du MacBook s'il existe, sinon celui sous le pointeur.
    static func defaultScreen() -> NSScreen? {
        NSScreen.screens.first(where: ScreenIdentifier.isBuiltIn) ?? screenUnderPointer()
    }

    static func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Écran où poser l'île selon le réglage.
    @MainActor
    static func targetScreen(settings: OtterSettings) -> NSScreen? {
        switch settings.islandScreenMode {
        case .fixed:
            let id = settings.islandFixedScreenID
            // Écran choisi débranché : on retombe sur l'écran par défaut, et on
            // y revient tout seul quand il est rebranché.
            return NSScreen.screens.first { !id.isEmpty && ScreenIdentifier.stableID(for: $0) == id }
                ?? defaultScreen()
        case .pointer, .everyScreen:
            return screenUnderPointer()
        }
    }
}
