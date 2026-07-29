import AppKit
import Carbon.HIToolbox

/// Raccourci clavier global via Carbon (RegisterEventHotKey). Consomme la combinaison
/// au niveau système. Le handler est appelé sur le thread principal.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    /// false si `RegisterEventHotKey` a échoué (combinaison déjà prise par une
    /// autre app/le système, par exemple) : jusque-là ignoré en silence, ce qui
    /// laissait la frappe passer telle quelle sans que rien ne se déclenche.
    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
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
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let instance = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                instance.handler()
                return noErr
            },
            1, &spec, selfPtr, &eventHandler
        )

        let id = EventHotKeyID(signature: OSType(0x4F545231), id: 1) // 'OTR1'
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        isRegistered = status == noErr
        if !isRegistered {
            NSLog("OtterIsland: échec de l'enregistrement du raccourci presse-papier (OSStatus \(status)) — combinaison déjà prise ?")
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
