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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.system(size: 16))
                .foregroundStyle(.black.opacity(0.4))
            Text("Caméra non autorisée")
                .font(.subheadline)
                .foregroundStyle(.black.opacity(0.7))
            Button("Ouvrir les réglages") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
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
