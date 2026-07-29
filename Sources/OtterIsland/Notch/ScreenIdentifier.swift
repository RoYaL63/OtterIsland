import AppKit
import CoreGraphics

/// Identifiant stable d'un écran, utilisé pour les réglages par écran.
/// Le `CGDirectDisplayID` change parfois d'une session à l'autre selon l'ordre
/// de connexion : on préfère vendor/modèle/série, avec un repli sur "intégré"
/// ou la résolution pour les écrans qui n'exposent pas de série exploitable.
enum ScreenIdentifier {
    /// L'écran intégré du MacBook (Retina/notch), s'il y en a un sur ce Mac.
    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    static func stableID(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "unknown-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        }
        let displayID = CGDirectDisplayID(number.uint32Value)

        if CGDisplayIsBuiltin(displayID) != 0 {
            return "built-in"
        }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        if serial != 0 {
            return "ext-\(vendor)-\(model)-\(serial)"
        }
        // Pas de série exploitable (fréquent sur les écrans bon marché) : la résolution
        // suffit à distinguer les moniteurs d'un même setup.
        return "ext-\(vendor)-\(model)-\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    /// Libellé lisible pour les réglages ("Built-in Retina Display", "DELL U2723QE"...).
    static func label(for screen: NSScreen) -> String {
        let name = screen.localizedName
        return name.isEmpty ? "Écran \(Int(screen.frame.width))×\(Int(screen.frame.height))" : name
    }
}
