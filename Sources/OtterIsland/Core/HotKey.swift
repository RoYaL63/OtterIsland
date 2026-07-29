import AppKit
import Carbon.HIToolbox

/// Raccourci clavier global via Carbon (RegisterEventHotKey). Consomme la combinaison
/// au niveau système. Le handler est appelé sur le thread principal.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

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
        RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
