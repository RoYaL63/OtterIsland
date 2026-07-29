import AppKit

/// Verrouille le clavier entier (CGEventTap qui avale toutes les frappes) pour
/// pouvoir nettoyer les touches sans rien déclencher. Se déverrouille au clic
/// dans l'encoche — jamais au clavier, puisqu'il est justement bloqué.
///
/// Nécessite l'autorisation Accessibilité (déjà demandée ailleurs pour le
/// collage auto) ; `CGEvent.tapCreate` renvoie nil sans elle.
@MainActor
final class KeyboardLocker: ObservableObject {
    @Published private(set) var isLocked = false
    /// true si macOS a refusé la création du tap (permission manquante).
    @Published private(set) var permissionDenied = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func toggle() {
        isLocked ? unlock() : lock()
    }

    func lock() {
        guard eventTap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let locker = Unmanaged<KeyboardLocker>.fromOpaque(refcon).takeUnretainedValue()
                // Le système désactive parfois le tap tout seul (charge, timeout) :
                // sans ça, le clavier se déverrouillerait silencieusement.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = locker.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }
                return nil // avale la frappe : rien ne remonte, nulle part
            },
            userInfo: refcon
        ) else {
            permissionDenied = true
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        permissionDenied = false
        isLocked = true
    }

    func unlock() {
        permissionDenied = false
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isLocked = false
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}
