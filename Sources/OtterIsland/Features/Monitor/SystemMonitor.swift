import Foundation
import Darwin

/// Relevé de ce qui consomme les ressources du Mac.
///
/// Ce qu'on peut lire, et ce qu'on ne peut pas — autant le dire ici plutôt que
/// de laisser croire à un capteur qui n'existe pas :
///
/// - **Lisible sans privilège** : le CPU et la mémoire par processus (`ps`), la
///   charge moyenne (`getloadavg`), et l'état thermique tel que le système le
///   déclare (`ProcessInfo.thermalState`). C'est ce dernier qui répond à « mon
///   Mac chauffe » : macOS y résume lui-même sa pression thermique.
/// - **NON lisible** : la température des cœurs et la vitesse des ventilateurs.
///   Elles vivent dans le SMC, dont la lecture demande soit `powermetrics` en
///   root, soit un helper privilégié installé à part. Une app normale n'y a pas
///   accès, et prétendre le contraire en affichant un chiffre inventé serait
///   pire que de ne rien afficher.
///
/// Le relevé ne tourne QUE quand l'onglet est visible (`start()` / `stop()`) :
/// un `ps` toutes les 5 secondes en permanence ferait de ce moniteur l'une des
/// choses qui consomment.
@MainActor
final class SystemMonitor: ObservableObject {

    struct ProcessUsage: Identifiable, Equatable {
        let id: Int32
        let name: String
        /// Pourcentage d'UN cœur : 100 % = un cœur saturé, 800 % = huit.
        let cpu: Double
        let memoryMB: Double
    }

    @Published private(set) var topByCPU: [ProcessUsage] = []
    @Published private(set) var topByMemory: [ProcessUsage] = []
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    /// Charge moyenne sur 1 min, ramenée au nombre de cœurs : 1,0 = machine
    /// pleine. Un chiffre brut « 8,2 » ne veut rien dire sans savoir combien de
    /// cœurs a la machine.
    @Published private(set) var loadRatio: Double = 0
    @Published private(set) var lastRefresh: Date?

    private var timer: Timer?

    var coreCount: Int { ProcessInfo.processInfo.processorCount }

    /// Somme des pourcentages CPU rapportée au nombre de cœurs, 0…1.
    var cpuUsage: Double {
        let total = topByCPU.reduce(0) { $0 + $1.cpu }
        return min(1, total / (Double(coreCount) * 100))
    }

    func start() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        thermalState = ProcessInfo.processInfo.thermalState
        loadRatio = Self.loadAverage() / Double(coreCount)
        let all = Self.sampleProcesses()
        topByCPU = Array(all.sorted { $0.cpu > $1.cpu }.prefix(6))
        topByMemory = Array(all.sorted { $0.memoryMB > $1.memoryMB }.prefix(6))
        lastRefresh = Date()
    }

    // MARK: Relevé

    /// `ps` plutôt que l'API `proc_pidinfo` : cette dernière donne des tics CPU
    /// cumulés depuis le lancement du processus, qu'il faudrait dériver soi-même
    /// entre deux relevés. `ps` fait déjà ce calcul, et c'est la même source que
    /// le Moniteur d'activité.
    private static func sampleProcesses() -> [ProcessUsage] {
        guard let output = shell(["-Aceo", "pid=,pcpu=,rss=,comm="]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2])
            else { return nil }
            let name = parts[3...].joined(separator: " ")
            // Le processus `ps` lui-même et les tâches système à 0 partout ne
            // valent pas une ligne dans un diagnostic.
            guard cpu > 0 || rssKB > 0 else { return nil }
            return ProcessUsage(id: pid, name: name, cpu: cpu, memoryMB: rssKB / 1024)
        }
    }

    private static func loadAverage() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) > 0 else { return 0 }
        return loads[0]
    }

    private static func shell(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Matériel

    /// Identifiant machine (« Mac15,3 ») — utile dans un rapport qu'on envoie.
    static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "inconnu" }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(cString: value)
    }

    static var chip: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "inconnu" }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &value, &size, nil, 0)
        return String(cString: value)
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return "Normal"
        case .fair: return "Tiède"
        case .serious: return "Chaud"
        case .critical: return "Critique"
        @unknown default: return "Inconnu"
        }
    }

    /// Ce que macOS fait DÉJÀ à cet état : c'est plus utile que l'état seul.
    var explanation: String {
        switch self {
        case .nominal: return "Aucune limitation en cours."
        case .fair: return "Ventilateurs en hausse, aucune limitation notable."
        case .serious: return "Le système bride les performances pour faire baisser la température."
        case .critical: return "Bridage fort. macOS peut suspendre des tâches de fond."
        @unknown default: return ""
        }
    }
}
