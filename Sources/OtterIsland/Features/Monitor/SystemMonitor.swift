import Foundation
import Darwin
import AppKit

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
        /// Processus parent : c'est lui qui permet de rattacher les cinq
        /// « Google Chrome Helper » à Google Chrome.
        let parent: Int32
        let name: String
        /// Pourcentage d'UN cœur : 100 % = un cœur saturé, 800 % = huit.
        let cpu: Double
        let memoryMB: Double
    }

    /// Consommation regroupée par application — la vue utile. Les processus
    /// bruts restent disponibles pour le rapport et le détail.
    @Published private(set) var apps: [AppUsage] = []
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

    /// Compteur d'utilisateurs du relevé. La carte de l'encoche ET la fenêtre
    /// détaillée peuvent l'observer en même temps : sans ce comptage, fermer
    /// l'une arrêterait le relevé de l'autre.
    private var subscribers = 0

    func start() {
        subscribers += 1
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        thermalState = ProcessInfo.processInfo.thermalState
        loadRatio = Self.loadAverage() / Double(coreCount)
        let all = Self.sampleProcesses()
        topByCPU = Array(all.sorted { $0.cpu > $1.cpu }.prefix(6))
        topByMemory = Array(all.sorted { $0.memoryMB > $1.memoryMB }.prefix(6))
        apps = Self.group(all)
        lastRefresh = Date()
    }

    // MARK: Relevé

    /// `ps` plutôt que l'API `proc_pidinfo` : cette dernière donne des tics CPU
    /// cumulés depuis le lancement du processus, qu'il faudrait dériver soi-même
    /// entre deux relevés. `ps` fait déjà ce calcul, et c'est la même source que
    /// le Moniteur d'activité.
    private static func sampleProcesses() -> [ProcessUsage] {
        guard let output = shell(["-Aceo", "pid=,ppid=,pcpu=,rss=,comm="]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let cpu = Double(parts[2]),
                  let rssKB = Double(parts[3])
            else { return nil }
            let name = parts[4...].joined(separator: " ")
            // Le processus `ps` lui-même et les tâches système à 0 partout ne
            // valent pas une ligne dans un diagnostic.
            guard cpu > 0 || rssKB > 0 else { return nil }
            return ProcessUsage(id: pid, parent: ppid, name: name, cpu: cpu, memoryMB: rssKB / 1024)
        }
    }

    /// Rattache chaque processus à son application en remontant la chaîne des
    /// parents jusqu'à un PID connu de `NSWorkspace`. Un helper de Chrome a pour
    /// parent le processus Chrome principal ; deux ou trois sauts suffisent.
    /// Ce qui ne se rattache à rien reste tel quel : ce sont les démons système,
    /// qui méritent d'apparaître sous leur propre nom.
    private static func group(_ processes: [ProcessUsage]) -> [AppUsage] {
        let running = NSWorkspace.shared.runningApplications
        var appInfo: [pid_t: (name: String, bundleID: String?)] = [:]
        for app in running where app.processIdentifier > 0 {
            appInfo[app.processIdentifier] = (
                app.localizedName ?? app.bundleIdentifier ?? "Application",
                app.bundleIdentifier
            )
        }

        let parents = Dictionary(processes.map { ($0.id, $0.parent) }, uniquingKeysWith: { a, _ in a })

        /// Remonte au plus 8 niveaux : au-delà, on est dans launchd et le
        /// rattachement n'aurait plus de sens.
        func owner(of pid: pid_t) -> pid_t? {
            var current = pid
            for _ in 0..<8 {
                if appInfo[current] != nil { return current }
                guard let next = parents[current], next > 1 else { return nil }
                current = next
            }
            return nil
        }

        var groups: [pid_t: AppUsage] = [:]
        for process in processes {
            let ownerPID = owner(of: process.id)
            let key = ownerPID ?? process.id
            let info = ownerPID.flatMap { appInfo[$0] }

            if var existing = groups[key] {
                existing.cpu += process.cpu
                existing.memoryMB += process.memoryMB
                existing.processCount += 1
                existing.processes.append(process)
                groups[key] = existing
            } else {
                groups[key] = AppUsage(
                    id: key,
                    name: info?.name ?? process.name,
                    bundleID: info?.bundleID,
                    cpu: process.cpu,
                    memoryMB: process.memoryMB,
                    processCount: 1,
                    isGUI: info != nil,
                    processes: [process]
                )
            }
        }

        return groups.values
            .map { group in
                var sorted = group
                sorted.processes.sort { $0.cpu > $1.cpu }
                return sorted
            }
            .sorted { $0.cpu > $1.cpu }
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
