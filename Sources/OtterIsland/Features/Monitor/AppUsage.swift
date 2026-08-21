import AppKit
import ApplicationServices

/// Consommation regroupée PAR APPLICATION, et non par processus.
///
/// Une liste de processus bruts ment par omission : Chrome y apparaît comme
/// cinq « Google Chrome Helper (Renderer) » à 15 % qu'on ne sait pas rattacher,
/// pendant qu'un onglet unique en consomme 80 à lui tout seul. Le Moniteur
/// d'activité d'Apple fait ce regroupement dans son onglet « Énergie » ; c'est
/// la même idée ici, obtenue en remontant la chaîne des processus parents
/// jusqu'à une application connue du système.
struct AppUsage: Identifiable, Equatable {
    /// PID du processus principal de l'application.
    let id: pid_t
    let name: String
    let bundleID: String?
    /// Somme des pourcentages CPU de tous ses processus (100 % = un cœur).
    var cpu: Double
    var memoryMB: Double
    var processCount: Int
    /// Application avec interface (elle a une icône, on peut la quitter
    /// proprement) plutôt que démon ou service système.
    let isGUI: Bool
    /// Les processus qui la composent, pour qui veut le détail.
    var processes: [SystemMonitor.ProcessUsage]

    /// « 3,2 Go » plutôt que « 3 252 Mo » : quatre chiffres volent la place du
    /// nom de l'application, qui est l'information la plus utile de la rangée.
    var memoryText: String {
        memoryMB >= 1024
            ? String(format: "%.1f Go", memoryMB / 1024).replacingOccurrences(of: ".", with: ",")
            : "\(Int(memoryMB)) Mo"
    }

    var icon: NSImage? {
        guard isGUI, let app = NSRunningApplication(processIdentifier: id) else { return nil }
        return app.icon
    }

    static func == (lhs: AppUsage, rhs: AppUsage) -> Bool {
        lhs.id == rhs.id && lhs.cpu == rhs.cpu && lhs.memoryMB == rhs.memoryMB
            && lhs.processCount == rhs.processCount
    }
}

/// Lecture des titres de fenêtres d'une application.
///
/// C'est la réponse la plus proche de « quel onglet ? » qu'on puisse obtenir de
/// l'extérieur : le titre de fenêtre de Chrome EST le titre de l'onglet actif.
/// Deux fenêtres Chrome donnent donc deux titres distincts, et une application
/// web installée (PWA) porte son propre nom.
///
/// Ce qui reste hors de portée, et il faut le dire plutôt que de le suggérer :
/// attribuer un pourcentage de CPU à UN onglet précis. Chrome garde pour lui la
/// correspondance entre ses processus « renderer » et ses onglets — son propre
/// gestionnaire de tâches (Fenêtre › Gestionnaire de tâches) est le seul endroit
/// où elle est visible.
enum WindowInspector {

    /// Nécessite l'autorisation Accessibilité, déjà demandée par le collage
    /// automatique. Sans elle, renvoie une liste vide : l'interface affiche
    /// alors une invite plutôt que de faire croire que l'app n'a pas de fenêtre.
    static func windowTitles(pid: pid_t, limit: Int = 6) -> [String] {
        guard AXIsProcessTrusted() else { return [] }
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return [] }

        var titles: [String] = []
        for window in windows.prefix(limit) {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &raw) == .success,
                  let title = raw as? String,
                  !title.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            titles.append(title)
        }
        return titles
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }
}

/// Arrêt d'une application depuis le moniteur.
enum ProcessTerminator {

    enum Outcome {
        case quitRequested   // demande polie envoyée, l'app peut proposer d'enregistrer
        case forced          // SIGKILL : rien n'est enregistré
        case failed(String)
    }

    /// Demande poliment d'abord. `terminate()` envoie l'équivalent de ⌘Q :
    /// l'application peut proposer d'enregistrer son travail. C'est le
    /// comportement attendu par défaut — tuer sans prévenir doit rester un
    /// choix explicite, pas la seule option offerte.
    static func quit(pid: pid_t) -> Outcome {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return .failed("Cette application n'est plus en cours d'exécution.")
        }
        return app.terminate() ? .quitRequested : .failed("macOS a refusé la demande de fermeture.")
    }

    /// SIGKILL. Le travail non enregistré est perdu : l'appelant DOIT avoir
    /// demandé confirmation avant.
    static func force(pid: pid_t) -> Outcome {
        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.forceTerminate() { return .forced }
        }
        // Processus sans interface : pas de NSRunningApplication, on passe par
        // le signal. Échoue proprement si le processus appartient à root.
        if kill(pid, SIGKILL) == 0 { return .forced }
        return .failed(errno == EPERM
                       ? "Ce processus appartient au système : OtterIsland n'a pas le droit de l'arrêter."
                       : "Arrêt impossible (code \(errno)).")
    }
}
