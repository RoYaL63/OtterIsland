import Foundation

/// Petit stockage JSON dans Application Support/OtterIsland. Utilisé pour garder
/// l'historique du presse-papier et l'étagère entre deux lancements.
enum Persistence {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("OtterIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url(name), options: .atomic)
        } catch {
            NSLog("OtterIsland: sauvegarde \(name) impossible — \(error.localizedDescription)")
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
