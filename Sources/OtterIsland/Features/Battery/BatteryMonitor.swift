import Foundation
import IOKit.ps

/// Lit l'état de la batterie via IOKit et se met à jour quand la source d'alimentation change.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var percentage: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    /// Minutes restantes (décharge) ou jusqu'à pleine charge. nil si en calcul.
    @Published private(set) var minutesRemaining: Int?

    private var runLoopSource: CFRunLoopSource?

    init() {
        refresh()
        startObserving()
    }

    private func startObserving() {
        // Le callback C reçoit un pointeur vers self pour repasser sur le main actor.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func refresh() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }

            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                percentage = Int((Double(current) / Double(max)) * 100.0)
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                isPluggedIn = (state == kIOPSACPowerValue)
            }
            if let charging = desc[kIOPSIsChargingKey] as? Bool {
                isCharging = charging
            }
            // -1 = macOS calcule encore l'estimation.
            let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = desc[key] as? Int {
                minutesRemaining = minutes >= 0 ? minutes : nil
            }
        }
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}
