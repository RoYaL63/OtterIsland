import Foundation
import IOKit

/// Lecture du SMC (System Management Controller) : vitesse des ventilateurs et
/// températures de la puce.
///
/// Le SMC est lisible sans privilège par n'importe quelle app non sandboxée via
/// le service IOKit `AppleSMC` — c'est ce que font Stats, iStat Menus ou
/// smcFanControl. Seule l'ÉCRITURE (piloter les ventilateurs) demande root, et
/// on ne s'en sert pas.
///
/// Ce qui reste incertain, et qu'il faut assumer : les clés de température
/// changent d'une génération de puce à l'autre (Intel, M1, M2, M3, M4…) et
/// Apple ne les documente pas. On interroge donc une liste de clés connues, on
/// écarte les valeurs aberrantes, et si rien ne répond, l'interface dit
/// « indisponible » au lieu d'inventer un chiffre.
final class SMCReader {

    struct Fan: Equatable {
        let index: Int
        let rpm: Double
        let minRPM: Double
        let maxRPM: Double

        /// Position entre le minimum et le maximum, 0…1. Un ventilateur au
        /// minimum n'est pas « à 30 % » : il est au repos.
        var level: Double {
            guard maxRPM > minRPM else { return 0 }
            return min(1, max(0, (rpm - minRPM) / (maxRPM - minRPM)))
        }
    }

    struct Snapshot: Equatable {
        /// Liste vide : Mac sans ventilateur (MacBook Air Apple Silicon) OU SMC
        /// illisible — `fanCountKnown` fait la différence.
        let fans: [Fan]
        let fanCountKnown: Bool
        /// Moyenne et maximum des sondes CPU lisibles, en °C.
        let cpuAverage: Double?
        let cpuMax: Double?
        let gpuAverage: Double?
        let batteryTemperature: Double?

        var hasTemperatures: Bool { cpuAverage != nil }
    }

    // MARK: Structures du pilote

    /// Miroir exact de `SMCKeyData_t` côté noyau : 80 octets. Le rembourrage
    /// explicite après `keyInfo` reproduit l'alignement C (keyInfo fait 9
    /// octets utiles mais en occupe 12).
    private struct KeyData {
        struct Version {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }
        struct PLimit {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpuPLimit: UInt32 = 0
            var gpuPLimit: UInt32 = 0
            var memPLimit: UInt32 = 0
        }
        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var dataAttributes: UInt8 = 0
        }
        typealias Bytes = (
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
            UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
        )

        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private static let handleYPCEvent: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9

    // MARK: Clés

    /// Sondes CPU connues. Intel : TC… ; Apple Silicon : Tp…/Te…/Tf… selon la
    /// génération. Les clés absentes échouent vite et sont mémorisées comme
    /// telles, on ne les redemande pas.
    private static let cpuKeys = [
        // Intel
        "TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TCXC", "TC1C", "TC2C", "TC3C", "TC4C",
        // M1
        "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
        // M2
        "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp0f", "Tp0j",
        // M3
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
        "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
        // M4
        "Te09", "Te0H", "Tp0V", "Tp0Y", "Tp0e",
    ]

    private static let gpuKeys = [
        // Intel
        "TG0D", "TG0P", "TCGC",
        // M1 / M2
        "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
        // M3
        "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A",
        // M4
        "Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0d", "Tg0e", "Tg0k",
    ]

    private static let batteryKeys = ["TB0T", "TB1T", "TB2T"]

    // MARK: Connexion

    private var connection: io_connect_t = 0
    private var isOpen = false
    /// Clés qui ont répondu au moins une fois / jamais. Évite 60 allers-retours
    /// IOKit inutiles à chaque relevé.
    private var missingKeys: Set<String> = []

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        isOpen = IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    deinit {
        if isOpen { IOServiceClose(connection) }
    }

    var isAvailable: Bool { isOpen }

    func snapshot() -> Snapshot? {
        guard isOpen else { return nil }

        var fans: [Fan] = []
        let fanCount = read("FNum").map { Int($0) }
        if let fanCount {
            for i in 0..<min(fanCount, 4) {
                guard let rpm = read("F\(i)Ac") else { continue }
                let minRPM = read("F\(i)Mn") ?? 0
                let maxRPM = read("F\(i)Mx") ?? 0
                fans.append(Fan(index: i, rpm: max(0, rpm), minRPM: minRPM, maxRPM: maxRPM))
            }
        }

        let cpu = temperatures(Self.cpuKeys)
        let gpu = temperatures(Self.gpuKeys)
        let battery = temperatures(Self.batteryKeys)

        return Snapshot(
            fans: fans,
            fanCountKnown: fanCount != nil,
            cpuAverage: cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count),
            cpuMax: cpu.max(),
            gpuAverage: gpu.isEmpty ? nil : gpu.reduce(0, +) / Double(gpu.count),
            batteryTemperature: battery.max()
        )
    }

    /// Valeurs plausibles seulement : une sonde débranchée renvoie 0, -127 ou
    /// des octets sans signification.
    private func temperatures(_ keys: [String]) -> [Double] {
        keys.compactMap { key in
            guard let value = read(key), value > 10, value < 130 else { return nil }
            return value
        }
    }

    // MARK: Lecture brute

    private func read(_ key: String) -> Double? {
        guard !missingKeys.contains(key), let code = Self.fourCC(key) else { return nil }

        var input = KeyData()
        input.key = code
        input.data8 = Self.cmdGetKeyInfo
        guard let info = call(&input), info.result == 0, info.keyInfo.dataSize > 0 else {
            missingKeys.insert(key)
            return nil
        }

        var readInput = KeyData()
        readInput.key = code
        readInput.keyInfo.dataSize = info.keyInfo.dataSize
        readInput.data8 = Self.cmdReadKey
        guard let output = call(&readInput), output.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(min(32, info.keyInfo.dataSize)))) }
        return Self.decode(bytes, type: Self.string(from: info.keyInfo.dataType))
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            Self.handleYPCEvent,
            &input,
            MemoryLayout<KeyData>.stride,
            &output,
            &outputSize
        )
        return result == kIOReturnSuccess ? output : nil
    }

    /// Les formats du SMC. Apple Silicon parle surtout en `flt ` (flottant
    /// 32 bits petit-boutiste), Intel en virgule fixe gros-boutiste.
    private static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let value = Double(Float(bitPattern: raw))
            return value.isFinite ? value : nil
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }

    private static func fourCC(_ key: String) -> UInt32? {
        let scalars = Array(key.utf8)
        guard scalars.count == 4 else { return nil }
        return scalars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
