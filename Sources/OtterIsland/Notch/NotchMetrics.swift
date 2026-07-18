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

    static func current(for screen: NSScreen, widthOffset: CGFloat = 0) -> NotchMetrics {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        var width: CGFloat = 200 // secours pour un Mac sans encoche
        var hasReal = false

        // Sur un Mac à encoche, les zones auxiliaires bordent le notch.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let computed = frame.width - left.width - right.width
            if computed > 0 {
                width = computed
                hasReal = true
            }
        }

        let height: CGFloat = topInset > 0 ? topInset : 32
        let finalWidth = max(120, width + widthOffset)

        return NotchMetrics(
            screen: screen,
            screenFrame: frame,
            notchSize: CGSize(width: finalWidth, height: height),
            hasRealNotch: hasReal
        )
    }

    /// Écran sous le curseur, sinon écran principal.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
