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

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenerBlock: AudioObjectPropertyListenerBlock?

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
    }

    private func readVolume() -> Float {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &value)
        return status == noErr ? Float(value) : volume
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
    }
}
