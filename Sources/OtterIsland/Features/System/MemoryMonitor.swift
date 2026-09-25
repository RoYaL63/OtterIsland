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
    /// Ventilation détaillée, au sens du Moniteur d'activité.
    @Published private(set) var breakdown: Breakdown?
    /// Pages écrites dans le swap par seconde, entre les deux derniers relevés.
    /// C'est LE signe d'un Mac qui manque de RAM : tant qu'il est à zéro, une
    /// mémoire « pleine » n'est qu'un cache bien rempli.
    @Published private(set) var swapOutsPerSecond: Double = 0

    /// Ce que contient la RAM, en octets. Les mêmes catégories que le Moniteur
    /// d'activité, calculées de la même façon :
    /// - app = pages anonymes (internal) moins ce qui est purgeable ;
    /// - câblée = verrouillée par le noyau, jamais compressée ni swappée ;
    /// - compressée = ce qu'occupe le compresseur (pas ce qu'il contient) ;
    /// - cache = fichiers récemment lus + purgeable, rendu instantanément à qui
    ///   en a besoin : ce n'est PAS de la mémoire « perdue ».
    struct Breakdown: Equatable {
        let total: Double
        let app: Double
        let wired: Double
        let compressed: Double
        let cached: Double
        let free: Double
        let swapUsed: Double
        let swapTotal: Double

        var used: Double { app + wired + compressed }
        var fraction: Double { total > 0 ? min(1, used / total) : 0 }
    }

    private var lastSwapOuts: UInt64?
    private var lastSampleDate: Date?

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

        let purgeable = Double(stats.purgeable_count)
        let app = max(0, Double(stats.internal_page_count) - purgeable) * pageSize
        let swap = Self.swapUsage()
        breakdown = Breakdown(
            total: total,
            app: app,
            wired: Double(stats.wire_count) * pageSize,
            compressed: Double(stats.compressor_page_count) * pageSize,
            cached: (Double(stats.external_page_count) + purgeable) * pageSize,
            free: Double(stats.free_count) * pageSize,
            swapUsed: swap.used,
            swapTotal: swap.total
        )

        let now = Date()
        if let lastSwapOuts, let lastSampleDate, stats.swapouts >= lastSwapOuts {
            let elapsed = now.timeIntervalSince(lastSampleDate)
            if elapsed > 0 {
                swapOutsPerSecond = Double(stats.swapouts - lastSwapOuts) / elapsed
            }
        }
        lastSwapOuts = stats.swapouts
        lastSampleDate = now
    }

    /// Relevé à la demande (bouton Actualiser, ouverture de la fenêtre) sans
    /// attendre le prochain tic de 10 s.
    func refresh() {
        sample()
    }

    /// `vm.swapusage` : le fichier d'échange sur le SSD. macOS l'agrandit à la
    /// demande ; un swap de plusieurs Go qui ne redescend pas signifie que la
    /// RAM ne suffit plus pour ce qu'on garde ouvert.
    private static func swapUsage() -> (used: Double, total: Double) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (Double(usage.xsu_used), Double(usage.xsu_total))
    }

    deinit {
        source?.cancel()
    }
}
