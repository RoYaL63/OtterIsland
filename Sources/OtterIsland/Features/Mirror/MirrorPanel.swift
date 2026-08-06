import SwiftUI
import AVFoundation
import AppKit

/// Panneau Miroir : aperçu de la caméra frontale. La session ne tourne que
/// tant que l'onglet est affiché.
struct MirrorPanel: View {
    @State private var authStatus = AVCaptureDevice.authorizationStatus(for: .video)

    var body: some View {
        Group {
            switch authStatus {
            case .denied, .restricted:
                deniedHint
            default:
                CameraPreview()
                    .clipShape(RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous))
                    .overlay(
                        SpecularRim(
                            shape: RoundedRectangle(cornerRadius: Otter.Radius.large, style: .continuous),
                            strength: 0.8
                        )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedHint: some View {
        VStack(spacing: 8) {
            OtterIconBadge(icon: "camera.fill", tint: Otter.warning, size: 34)
            Text("Caméra non autorisée")
                .font(.otterBody)
                .foregroundStyle(Otter.warning)
            OtterActionLink(title: "Ouvrir les réglages", icon: "gear", tint: Otter.warning) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

/// Vue AppKit qui affiche l'aperçu caméra via AVCaptureVideoPreviewLayer.
final class CameraPreviewNSView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        // .resizeAspect (et non .resizeAspectFill) : on voit tout le champ de la
        // caméra, quitte à avoir des bandes, plutôt qu'un recadrage qui coupe le visage.
        previewLayer.videoGravity = .resizeAspect
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

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            DispatchQueue.main.async { self.configureAndRun() }
        }
    }

    private func configureAndRun() {
        guard session.inputs.isEmpty else { return }
        let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
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
    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {}

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.stop()
    }
}
