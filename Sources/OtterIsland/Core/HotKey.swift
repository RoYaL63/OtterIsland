import AppKit
import Carbon.HIToolbox

/// Raccourci clavier global via Carbon (RegisterEventHotKey). Consomme la combinaison
/// au niveau système. Le handler est appelé sur le thread principal.
///
/// Chaque instance reçoit un identifiant UNIQUE et son gestionnaire vérifie que
/// l'événement la concerne. Avant, tous les raccourcis partageaient l'id 1 et
/// le gestionnaire ne regardait pas l'événement : avec deux raccourcis ou plus
/// (le mode Live en pose une douzaine), le premier gestionnaire appelé
/// répondait à toutes les combinaisons.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void
    private let identifier: UInt32

    private static var nextIdentifier: UInt32 = 1

    /// false si `RegisterEventHotKey` a échoué (combinaison déjà prise par une
    /// autre app/le système, par exemple) : jusque-là ignoré en silence, ce qui
    /// laissait la frappe passer telle quelle sans que rien ne se déclenche.
    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.identifier = HotKey.nextIdentifier
        HotKey.nextIdentifier += 1
        install(keyCode: keyCode, modifiers: modifiers)
    }

    private func install(keyCode: UInt32, modifiers: UInt32) {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressed
                )
                // Pas pour nous : on laisse passer au gestionnaire suivant.
                guard status == noErr, pressed.id == instance.identifier else {
                    return OSStatus(eventNotHandledErr)
                }
                instance.handler()
                return noErr
            },
            1, &spec, selfPtr, &eventHandler
        )

        let id = EventHotKeyID(signature: OSType(0x4F545231), id: identifier) // 'OTR1'
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        isRegistered = status == noErr
        if !isRegistered {
            NSLog("OtterIsland: échec de l'enregistrement d'un raccourci global (OSStatus \(status)) — combinaison déjà prise ?")
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
