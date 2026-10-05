import SwiftUI
import AVFoundation
import EventKit
import ApplicationServices

/// Page « Autorisations » : chaque accès que l'app peut demander, à quoi il
/// sert, s'il est accordé, et un bouton qui ouvre DIRECTEMENT le bon panneau
/// des Réglages Système. Avant, il fallait savoir où chercher.
struct PermissionsSettingsView: View {
    /// Les états changent dans les Réglages Système, hors de l'app : on les
    /// relit régulièrement tant que la page est affichée.
    @State private var tick = 0
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Emplacement") {
                    if AppInstall.needsRelocation {
                        Button("Hors /Applications — installer et relancer") {
                            AppInstall.installInApplications()
                        }
                        .foregroundStyle(.red)
                        .help("Lancée depuis \(AppInstall.humanLocation), les autorisations ne s'appliquent jamais (App Translocation).")
                    } else {
                        Label("/Applications", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } footer: {
                caption("Les autorisations ne tiennent que si l'app est dans le dossier Applications.")
            }

            Section {
                ForEach(Permission.allCases) { permission in
                    PermissionRow(permission: permission)
                }
            } header: {
                Text("Accès")
            } footer: {
                caption("« Ouvrir » affiche le bon panneau des Réglages Système : coche OtterIsland dans la liste. Tous les accès sont facultatifs, une fonction sans son accès est simplement indisponible. L'Accessibilité et la Surveillance des saisies ne sont prises en compte qu'au prochain lancement d'OtterIsland. Si une case est cochée mais que ça ne marche pas : décoche-la puis recoche-la.")
            }
        }
        .formStyle(.grouped)
        // `tick` force la relecture des états à chaque passage du minuteur.
        .id(tick)
        .onReceive(poll) { _ in tick &+= 1 }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: permission.icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(permission.title)
                    statusBadge
                }
                Text(permission.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Ouvrir") { permission.openSettings() }
                .help("Ouvre Réglages Système › \(permission.settingsPath)")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch permission.status {
        case .granted:
            Label(permission == .loginItems ? "activée" : "accordée", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .denied:
            Label("non accordée", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.orange)
        case .notAsked:
            Text(permission == .loginItems ? "désactivée" : "pas encore demandée")
                .font(.caption).foregroundStyle(.secondary)
        case .unknown:
            EmptyView()
        }
    }
}

/// Les accès que l'app peut demander, avec leur panneau des Réglages Système.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility, inputMonitoring, calendars, reminders, camera, automation, loginItems

    enum Status { case granted, denied, notAsked, unknown }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibilité"
        case .inputMonitoring: return "Surveillance des saisies"
        case .calendars: return "Calendriers"
        case .reminders: return "Rappels"
        case .camera: return "Caméra"
        case .automation: return "Automatisation"
        case .loginItems: return "Ouverture au démarrage"
        }
    }

    var icon: String {
        switch self {
        case .accessibility: return "accessibility"
        case .inputMonitoring: return "keyboard"
        case .calendars: return "calendar"
        case .reminders: return "checklist"
        case .camera: return "camera"
        case .automation: return "gearshape.2"
        case .loginItems: return "power"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: return "Coller depuis l'historique du presse-papier, masquer les clés pendant le Live, afficher les touches, titres de pages dans le Moniteur."
        case .inputMonitoring: return "Verrouiller le clavier pour le nettoyer (avec l'Accessibilité)."
        case .calendars: return "Agenda et prochain rendez-vous de l'accueil."
        case .reminders: return "Rappels à cocher depuis l'agenda."
        case .camera: return "Le miroir."
        case .automation: return "Lire et piloter Spotify ou Musique, bouton « Redémarrer » du Moniteur. Coche Spotify, Musique et Événements Système sous OtterIsland."
        case .loginItems: return "Lancer OtterIsland à l'ouverture de session (Réglages › Général)."
        }
    }

    /// Chemin affiché dans l'aide du bouton.
    var settingsPath: String {
        switch self {
        case .loginItems: return "Général › Ouverture"
        default: return "Confidentialité et sécurité › \(title)"
        }
    }

    private var settingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .calendars: anchor = "Privacy_Calendars"
        case .reminders: anchor = "Privacy_Reminders"
        case .camera: anchor = "Privacy_Camera"
        case .automation: anchor = "Privacy_Automation"
        case .loginItems:
            return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    func openSettings() {
        // Pour ces deux-là, la demande système ajoute d'abord OtterIsland à la
        // liste : sinon l'utilisateur ouvre le panneau et ne l'y trouve pas.
        switch self {
        case .accessibility: _ = Paster.ensureAccessibility()
        case .inputMonitoring: _ = CGRequestListenEventAccess()
        default: break
        }
        if let url = settingsURL { NSWorkspace.shared.open(url) }
    }

    var status: Status {
        switch self {
        case .accessibility:
            return Paster.hasAccessibility ? .granted : .denied
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .granted : .denied
        case .calendars:
            return Self.status(EKEventStore.authorizationStatus(for: .event))
        case .reminders:
            return Self.status(EKEventStore.authorizationStatus(for: .reminder))
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .granted
            case .notDetermined: return .notAsked
            default: return .denied
            }
        case .automation:
            // macOS ne laisse pas lire cet état sans envoyer un Apple Event.
            return .unknown
        case .loginItems:
            return LaunchAtLogin.isEnabled ? .granted : .notAsked
        }
    }

    private static func status(_ status: EKAuthorizationStatus) -> Status {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }
}
