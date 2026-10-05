import SwiftUI
import AVFoundation
import AppKit

/// Panneau Miroir : aperçu de la caméra choisie. La session ne tourne que
/// tant que l'onglet est affiché.
///
/// La carte est petite : on y choisit la caméra et le cadrage. Pour se
/// préparer vraiment (fond, mode Portrait, éclairage), la fenêtre Miroir
/// s'ouvre en grand et reste là pendant qu'on règle les effets.
struct MirrorPanel: View {
    @EnvironmentObject var settings: OtterSettings
    /// Ouvre la fenêtre Miroir ; `withEffects` ouvre aussi les effets vidéo.
    let onOpenWindow: (_ withEffects: Bool) -> Void
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch authStatus {
            case .denied, .restricted:
                MirrorDeniedHint()
            default:
                CameraPreview(
                    deviceID: settings.mirrorCameraID,
                    flipped: settings.mirrorFlipped,
                    fill: settings.mirrorFill
                )
                .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous))
                .overlay(
                    SpecularRim(
                        shape: RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous),
                        strength: 0.8
                    )
                )
                .overlay(alignment: .bottom) {
                    MirrorControls(compact: true) {
                        // Les effets vivent dans le Centre de contrôle : y aller
                        // ferait replier l'île et couper la caméra. La fenêtre,
                        // elle, reste ouverte pendant le réglage.
                        onOpenWindow(true)
                    } onExpand: {
                        onOpenWindow(false)
                    }
                    .padding(6)
                }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MirrorDeniedHint: View {
    var body: some View {
        VStack(spacing: 8) {
            OtterIconBadge(icon: "camera.fill", tint: Otter.warning, size: 34)
            Text("Caméra non autorisée")
                .font(.otterBody)
                .foregroundStyle(Otter.textPrimary)
            OtterActionLink(title: "Ouvrir les réglages", icon: "gear", tint: Otter.warning) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - Caméras disponibles

/// Caméras du Mac : intégrée, externes (USB) et iPhone en Caméra Continuité
/// (qui se présente comme une caméra grand-angle tant que l'app ne demande pas
/// le type dédié). Se met à jour quand on branche ou débranche.
@MainActor
final class CameraCatalog: ObservableObject {
    @Published private(set) var devices: [AVCaptureDevice] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func refresh() {
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    /// Caméra à utiliser : celle choisie si elle est branchée, sinon la
    /// frontale du Mac, sinon la première venue.
    static func device(for id: String) -> AVCaptureDevice? {
        if !id.isEmpty, let chosen = AVCaptureDevice(uniqueID: id), chosen.isConnected {
            return chosen
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }
}

// MARK: - Effets vidéo de macOS

/// Effets vidéo du système : arrière-plan, mode Portrait, Lumière studio,
/// Cadre centré, réactions. Une app ne peut pas les régler elle-même ; elle
/// peut lire leur état et ouvrir le module du Centre de contrôle, qui ne
/// s'affiche que pendant qu'elle utilise la caméra.
enum VideoEffects {
    struct Status: Equatable {
        var portrait = false
        var studioLight = false
        var centerStage = false
        var background = false
    }

    static func open() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    static var status: Status {
        var s = Status()
        s.portrait = AVCaptureDevice.isPortraitEffectEnabled
        s.studioLight = AVCaptureDevice.isStudioLightEnabled
        s.centerStage = AVCaptureDevice.isCenterStageEnabled
        if #available(macOS 15.0, *) {
            s.background = AVCaptureDevice.isBackgroundReplacementEnabled
        }
        return s
    }
}

// MARK: - Commandes

/// Barre de réglages posée sur l'image : caméra, miroir, cadrage, effets.
struct MirrorControls: View {
    @EnvironmentObject var settings: OtterSettings
    @StateObject private var catalog = CameraCatalog()
    /// Version carte (icônes seules) ou fenêtre (avec libellés).
    let compact: Bool
    let onEffects: () -> Void
    var onExpand: (() -> Void)?

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            cameraMenu
            toggleButton(
                compact ? nil : (settings.mirrorFlipped ? "Miroir" : "Comme en visio"),
                icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                isOn: settings.mirrorFlipped,
                help: settings.mirrorFlipped
                    ? "Image inversée, comme dans un miroir. Clique pour la voir telle que les autres te verront."
                    : "Image telle que les autres te verront en visio. Clique pour l'inverser comme un miroir."
            ) { settings.mirrorFlipped.toggle() }
            toggleButton(
                compact ? nil : (settings.mirrorFill ? "Remplir" : "Tout le champ"),
                icon: settings.mirrorFill
                    ? "arrow.up.left.and.arrow.down.right"
                    : "arrow.down.right.and.arrow.up.left",
                isOn: settings.mirrorFill,
                help: settings.mirrorFill ? "Image recadrée pour remplir le cadre." : "Tout le champ de la caméra, avec des bandes."
            ) { settings.mirrorFill.toggle() }
            Spacer(minLength: 0)
            pill(compact ? nil : "Fond et effets…", icon: "wand.and.stars",
                 help: "Arrière-plan, mode Portrait, Lumière studio, Cadre centré : les effets vidéo de macOS.",
                 action: onEffects)
            if let onExpand {
                pill(nil, icon: "arrow.up.forward.app", help: "Ouvrir le miroir en grand", action: onExpand)
            }
        }
    }

    private var cameraMenu: some View {
        Menu {
            Picker("Caméra", selection: $settings.mirrorCameraID) {
                Text("Automatique (caméra du Mac)").tag("")
                ForEach(catalog.devices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
            .pickerStyle(.inline)
        } label: {
            // Couleur et taille posées sur le contenu même : le libellé d'un
            // Menu macOS ignore celles héritées de la pastille.
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                if !compact {
                    Text(CameraCatalog.device(for: settings.mirrorCameraID)?.localizedName ?? "Caméra")
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(.white)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choisir la caméra")
        .modifier(PillStyle(isOn: false))
    }

    private func toggleButton(_ title: String?, icon: String, isOn: Bool, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                if let title { Text(title) }
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .modifier(PillStyle(isOn: isOn))
    }

    private func pill(_ title: String?, icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                if let title { Text(title) }
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .modifier(PillStyle(isOn: false))
    }
}

/// Pastille sombre lisible sur n'importe quelle image de caméra.
private struct PillStyle: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        content
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(isOn ? Otter.accent : Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
    }
}

// MARK: - Aperçu

/// Vue AppKit qui affiche l'aperçu caméra via AVCaptureVideoPreviewLayer.
final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var deviceID: String?
    private var mirrored = true

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.session = session
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) non supporté")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    /// Applique les réglages. Changer de caméra remplace l'entrée à chaud,
    /// sans arrêter la session.
    func apply(deviceID: String, flipped: Bool, fill: Bool) {
        // .resizeAspect par défaut : on voit tout le champ de la caméra, quitte
        // à avoir des bandes, plutôt qu'un recadrage qui coupe le visage.
        previewLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        mirrored = flipped
        applyMirroring()
        guard deviceID != self.deviceID else { return }
        self.deviceID = deviceID
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.configureAndRun() }
        }
    }

    private func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }

    private func configureAndRun() {
        guard let device = CameraCatalog.device(for: deviceID ?? ""),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        applyMirroring()
        guard !session.isRunning else { return }
        // start/stopRunning sont bloquants → file de fond, recommandé par Apple.
        // On capture la session localement plutôt que self (isolé MainActor) ;
        // AVCaptureSession est thread-safe pour ces deux appels.
        nonisolated(unsafe) let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        nonisolated(unsafe) let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let deviceID: String
    let flipped: Bool
    let fill: Bool

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView()
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.apply(deviceID: deviceID, flipped: flipped, fill: fill)
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.stop()
    }
}

// MARK: - Fenêtre Miroir

/// Le miroir en grand, pour se préparer avant une visio : une vraie fenêtre
/// qui reste ouverte pendant qu'on règle fond et effets dans le Centre de
/// contrôle (l'île, elle, se replierait dès que le pointeur la quitte).
@MainActor
final class MirrorWindowController {
    private var window: NSWindow?
    private let settings: OtterSettings

    init(settings: OtterSettings) {
        self.settings = settings
    }

    func show(withEffects: Bool) {
        let win = window ?? makeWindow()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        if withEffects {
            // Le module n'apparaît que si l'app utilise la caméra : on laisse
            // la session démarrer avant de le demander.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { VideoEffects.open() }
        }
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingView(rootView: MirrorWindowView().environmentObject(settings))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Miroir — OtterIsland"
        win.contentView = host
        win.isReleasedWhenClosed = false
        win.center()
        return win
    }
}

private struct MirrorWindowView: View {
    @EnvironmentObject var settings: OtterSettings
    @State private var effects = VideoEffects.status
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)
    /// L'état des effets change dans le Centre de contrôle, hors de l'app :
    /// on le relit régulièrement tant que la fenêtre est affichée.
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 10) {
            if authStatus == .denied || authStatus == .restricted {
                MirrorDeniedHint().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CameraPreview(
                    deviceID: settings.mirrorCameraID,
                    flipped: settings.mirrorFlipped,
                    fill: settings.mirrorFill
                )
                .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous))
                .overlay(alignment: .topLeading) { activeEffects.padding(10) }
                .overlay(alignment: .bottom) {
                    MirrorControls(compact: false) { VideoEffects.open() }
                        .padding(10)
                }
            }
            Text("Fond et effets sont ceux de macOS (Centre de contrôle › Effets vidéo). macOS les retient app par app : pense à les activer aussi dans ton app de visio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 320)
        .background(Color.black.opacity(0.92))
        .preferredColorScheme(.dark)
        .onReceive(poll) { _ in
            let now = VideoEffects.status
            if now != effects { effects = now }
        }
    }

    /// Effets actifs, en pastilles : on voit d'un coup d'œil ce qui est allumé.
    @ViewBuilder
    private var activeEffects: some View {
        let items: [(String, String, Bool)] = [
            ("Arrière-plan", "photo.on.rectangle", effects.background),
            ("Portrait", "person.crop.rectangle", effects.portrait),
            ("Lumière studio", "light.max", effects.studioLight),
            ("Cadre centré", "person.crop.square.badge.camera", effects.centerStage),
        ]
        HStack(spacing: 6) {
            ForEach(items.filter(\.2), id: \.0) { item in
                Label(item.0, systemImage: item.1)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Otter.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
            }
        }
    }
}
