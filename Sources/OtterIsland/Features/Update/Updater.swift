import AppKit
import Foundation
import Security

/// Mise à jour depuis l'app : télécharge la dernière release GitHub, remplace
/// le bundle sur place et relance. Plus de zip à aller chercher, dézipper,
/// glisser dans /Applications.
///
/// Deux bénéfices qui ne sautent pas aux yeux :
///
/// 1. **Pas de quarantaine.** Un zip téléchargé par le navigateur reçoit
///    l'attribut `com.apple.quarantine`, d'où le blocage Gatekeeper et le
///    `spctl --add` du README. Un téléchargement `URLSession` n'en met pas :
///    l'app mise à jour se lance directement.
/// 2. **Même chemin.** Le bundle est remplacé à l'endroit exact où il était
///    (/Applications/OtterIsland.app), donc pas d'App Translocation.
///
/// Ce qui N'EST PAS réglé ici : les permissions TCC (Accessibilité,
/// Surveillance des saisies) sont liées à la SIGNATURE de l'app. Tant que les
/// builds sont signées ad-hoc (une identité différente à chaque build), macOS
/// voit une app différente et redemande les autorisations. Le correctif est
/// côté CI — signer avec un certificat auto-signé STABLE, voir docs/SIGNING.md.
/// `signatureIsStable` ci-dessous dit à l'interface quoi promettre.
@MainActor
final class Updater: ObservableObject {

    struct Release: Equatable {
        let version: String
        let notes: String
        let assetURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Date du dernier contrôle réussi, pour l'afficher dans les réglages.
    @Published private(set) var lastCheck: Date?

    /// Dépôt interrogé. En dur : c'est la source de l'app, pas un réglage.
    private let owner = "RoYaL63"
    private let repo = "OtterIsland"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases")!
    }

    // MARK: Vérification

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task {
            do {
                let release = try await fetchLatest()
                lastCheck = Date()
                if Self.isNewer(release.version, than: currentVersion) {
                    state = .available(release)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func fetchLatest() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OtterIsland/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.message("Réponse inattendue de GitHub.")
        }
        guard http.statusCode == 200 else {
            throw UpdateError.message("GitHub a répondu \(http.statusCode). Réessaie plus tard.")
        }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        // On ne prend que le .zip : c'est ce que publie le workflow de release.
        guard let asset = payload.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let assetURL = URL(string: asset.browser_download_url),
              let pageURL = URL(string: payload.html_url)
        else {
            throw UpdateError.message("Cette release ne contient pas de .zip téléchargeable.")
        }

        return Release(
            version: payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            notes: payload.body ?? "",
            assetURL: assetURL,
            pageURL: pageURL
        )
    }

    /// Comparaison composant par composant : "0.1.10" est plus récent que
    /// "0.1.9", ce qu'une comparaison de chaînes rate.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Installation

    func install(_ release: Release) {
        state = .downloading(0)
        Task {
            do {
                let zip = try await download(release.assetURL)
                state = .installing
                try await replaceBundle(withZipAt: zip)
                relaunch()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Téléchargement en flux, pour pouvoir afficher une progression : la
    /// variante `URLSession.download` ne la donne pas sans délégué.
    private func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("OtterIsland/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.message("Téléchargement impossible.")
        }
        let expected = http.expectedContentLength

        var data = Data()
        if expected > 0 { data.reserveCapacity(Int(expected)) }
        var lastReported = 0.0
        for try await byte in bytes {
            data.append(byte)
            if expected > 0 {
                let progress = Double(data.count) / Double(expected)
                // Republier à chaque octet ferait ramer l'UI plus que le réseau.
                if progress - lastReported > 0.01 {
                    lastReported = progress
                    state = .downloading(progress)
                }
            }
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("OtterIsland-update-\(UUID().uuidString).zip")
        try data.write(to: destination)
        return destination
    }

    /// Dézippe à côté du bundle actuel (même volume, condition de
    /// `replaceItemAt`) puis échange les deux atomiquement.
    private func replaceBundle(withZipAt zip: URL) async throws {
        let fm = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let parent = bundleURL.deletingLastPathComponent()

        guard fm.isWritableFile(atPath: parent.path) else {
            throw UpdateError.message(
                "Pas les droits d'écriture dans \(parent.path). Installe la mise à jour à la main depuis la page des releases."
            )
        }

        let staging = parent.appendingPathComponent(".OtterIslandUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        // `ditto` plutôt que `unzip` : il préserve les liens symboliques et les
        // attributs étendus d'un bundle .app, ce qu'`unzip` casse.
        try await runDitto(zip: zip, into: staging)
        try? fm.removeItem(at: zip)

        let contents = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.message("Le zip téléchargé ne contient pas d'app.")
        }

        // Ceinture et bretelles : si le téléchargement a été tronqué, mieux vaut
        // s'arrêter ici que remplacer l'app par une coquille vide.
        let executable = newApp.appendingPathComponent("Contents/MacOS/OtterIsland")
        guard fm.fileExists(atPath: executable.path) else {
            throw UpdateError.message("L'app téléchargée est incomplète, mise à jour annulée.")
        }

        _ = try fm.replaceItemAt(bundleURL, withItemAt: newApp)
    }

    private func runDitto(zip: URL, into directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, directory.path]
        let errPipe = Pipe()
        process.standardError = errPipe

        try await Task.detached(priority: .userInitiated) {
            try process.run()
            process.waitUntilExit()
        }.value

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw UpdateError.message("Décompression impossible. \(message)")
        }
    }

    /// Lance la nouvelle instance puis quitte celle-ci.
    private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Signature

    /// true si l'app est signée avec une identité stable (certificat nommé), et
    /// non ad-hoc. Détermine si les permissions survivront à la mise à jour :
    /// autant le dire honnêtement dans l'interface plutôt que de laisser
    /// l'utilisateur le découvrir après coup.
    static var signatureIsStable: Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code
        else { return false }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return false }

        // Une signature ad-hoc n'a pas d'autorité de signature.
        let key = kSecCodeInfoCertificates as String
        guard let authorities = dict[key] as? [Any], !authorities.isEmpty else {
            return false
        }
        return true
    }

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }
}

// MARK: - Charge utile GitHub

private struct GitHubRelease: Decodable {
    let tag_name: String
    let body: String?
    let html_url: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
}
