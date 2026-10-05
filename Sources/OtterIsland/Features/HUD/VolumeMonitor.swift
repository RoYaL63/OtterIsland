import Foundation
import CoreAudio

/// Observe le volume de la sortie audio par défaut via CoreAudio et publie ses
/// changements. Sert à afficher un HUD de volume dans l'encoche.
///
/// Note : ceci n'écrase pas encore le HUD natif de macOS (il faudrait suspendre
/// OSDUIHelper). On affiche le nôtre en plus, en attendant.
@MainActor
final class VolumeMonitor: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerBlock: AudioObjectPropertyListenerBlock?

    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        deviceID = Self.defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return }
        volume = readVolume()

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.volume = self.readVolume()
            }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)

        isMuted = readMute()
        let muteBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isMuted = self.readMute()
            }
        }
        muteListenerBlock = muteBlock
        AudioObjectAddPropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, muteBlock)
    }

    /// Règle le volume de sortie (0…1). Certaines sorties n'exposent pas de
    /// volume global, seulement un par canal : on règle alors gauche et droite.
    func setVolume(_ value: Float) {
        guard deviceID != kAudioObjectUnknown else { return }
        var level = Float32(min(max(value, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        if isSettable(&volumeAddress) {
            AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &level)
        } else {
            for channel: UInt32 in [1, 2] {
                var address = volumeAddress
                address.mElement = channel
                if isSettable(&address) {
                    AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &level)
                }
            }
        }
        // Monter le son doit le rétablir, comme les touches du clavier.
        if isMuted, level > 0 { setMuted(false) }
    }

    func toggleMute() { setMuted(!isMuted) }

    private func setMuted(_ muted: Bool) {
        guard deviceID != kAudioObjectUnknown, isSettable(&muteAddress) else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// La sortie permet-elle de couper le son ? (Certaines sorties HDMI non.)
    var canMute: Bool { deviceID != kAudioObjectUnknown && isSettable(&muteAddress) }

    private func isSettable(_ address: inout AudioObjectPropertyAddress) -> Bool {
        guard AudioObjectHasProperty(deviceID, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr && settable.boolValue
    }

    private func readMute() -> Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &value) == noErr && value != 0
    }

    private func readVolume() -> Float {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &value) == noErr {
            return Float(value)
        }
        // Pas de volume global : celui du canal gauche fait foi.
        var left = volumeAddress
        left.mElement = 1
        return AudioObjectGetPropertyData(deviceID, &left, 0, nil, &size, &value) == noErr ? Float(value) : volume
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return device
    }

    deinit {
        if let block = listenerBlock, deviceID != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(deviceID, &volumeAddress, DispatchQueue.main, block)
        }
        if let block = muteListenerBlock, deviceID != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(deviceID, &muteAddress, DispatchQueue.main, block)
        }
    }
}
