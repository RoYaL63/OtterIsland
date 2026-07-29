import Foundation

/// Surveille la mémoire : pression système (source Dispatch, la même notion que
/// la jauge du Moniteur d'activité) + fraction utilisée échantillonnée via
/// host_statistics64. La loutre s'inquiète quand la RAM sature, et le panneau
/// de statut affiche le pourcentage.
@MainActor
final class MemoryMonitor: ObservableObject {
    enum Pressure {
        case normal, warning, critical
    }

    @Published private(set) var pressure: Pressure = .normal
    /// Fraction 0...1 de RAM « utilisée » au sens Moniteur d'activité
    /// (active + wired + compressée).
    @Published private(set) var usedFraction: Double = 0

    private var source: DispatchSourceMemoryPressure?
    private var timer: Timer?

    func start() {
        guard source == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.handlePressureEvent()
        }
        src.resume()
        source = src

        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        timer?.invalidate()
        timer = nil
    }

    private func handlePressureEvent() {
        guard let source else { return }
        let event = source.data
        if event.contains(.critical) {
            pressure = .critical
        } else if event.contains(.warning) {
            pressure = .warning
        } else {
            pressure = .normal
        }
    }

    private func sample() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        // vm_page_size est une globale C mutable (non concurrency-safe au sens
        // Swift 6) ; sysconf(_SC_PAGESIZE) donne la même valeur proprement.
        let pageSize = Double(sysconf(_SC_PAGESIZE))
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return }
        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        usedFraction = min(1, max(0, used / total))
    }

    deinit {
        source?.cancel()
    }
}
