import AVFoundation
import SwiftUI
import UIKit

/// Capture photo dans l'application, et nulle part ailleurs.
///
/// Invariant 5 : la caméra est le seul accès aux médias. Aucun `PHPickerViewController`,
/// aucun accès à la photothèque, aucun import de fichier. Une preuve qui
/// pourrait venir de la pellicule ne prouverait plus rien — n'importe quelle
/// image trouvée ferait l'affaire.
@MainActor
@Observable
final class CameraSession {

    enum State: Equatable {
        case idle
        case ready
        case denied
        case unavailable(String)
    }

    private(set) var state: State = .idle

    /// Session AVFoundation, nulle sur simulateur.
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var configured = false

    /// Demande l'accès puis monte la session.
    func start() async {
        #if targetEnvironment(simulator)
        // Le simulateur n'a pas de caméra. Le test porte sur l'environnement
        // de compilation, pas sur un échec de `AVCaptureDevice.default` : un
        // appareil réel dont la caméra tombe en panne doit remonter une vraie
        // erreur, pas se rabattre silencieusement sur une image de synthèse.
        state = .ready
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        case .denied, .restricted:
            state = .denied
            return
        @unknown default:
            state = .denied
            return
        }

        guard configure() else { return }

        // `startRunning` bloque : hors du fil principal, sinon l'écran se fige
        // une demi-seconde au moment où il apparaît.
        let session = session
        await Task.detached(priority: .userInitiated) { session.startRunning() }.value
        state = .ready
        #endif
    }

    func stop() {
        #if !targetEnvironment(simulator)
        let session = session
        Task.detached(priority: .utility) { session.stopRunning() }
        #endif
    }

    #if !targetEnvironment(simulator)
    private func configure() -> Bool {
        guard !configured else { return true }

        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            state = .unavailable("La caméra n'est pas disponible sur cet appareil.")
            return false
        }

        session.addInput(input)
        session.addOutput(output)
        configured = true
        return true
    }
    #endif

    /// Prend une photo et rend ses octets JPEG.
    ///
    /// Ce sont ces octets exacts qui seront hachés puis envoyés : le hash doit
    /// porter sur ce qui part, pas sur l'image en mémoire.
    func capture(goalID: UUID) async throws -> Data {
        #if targetEnvironment(simulator)
        return SimulatorCamera.image(goalID: goalID)
        #else
        guard state == .ready else {
            throw AppError.server(message: "La caméra n'est pas prête.")
        }

        let settings = AVCapturePhotoSettings(format: [
            AVVideoCodecKey: AVVideoCodecType.jpeg.rawValue,
        ])

        let delegate = PhotoCaptureDelegate()
        return try await withCheckedThrowingContinuation { continuation in
            delegate.onFinish = { result in
                continuation.resume(with: result)
            }
            // Le délégué doit survivre à l'appel : AVFoundation ne le retient
            // pas, et un délégué libéré trop tôt fait disparaître la photo
            // sans la moindre erreur.
            self.pendingDelegate = delegate
            self.output.capturePhoto(with: settings, delegate: delegate)
        }
        #endif
    }

    #if !targetEnvironment(simulator)
    private var pendingDelegate: PhotoCaptureDelegate?
    #endif
}

#if !targetEnvironment(simulator)
/// Pont entre le délégué AVFoundation, qui n'est pas `Sendable`, et
/// `async/await`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    var onFinish: ((Result<Data, Error>) -> Void)?

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            onFinish?(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            onFinish?(.failure(AppError.server(message: "La photo n'a pas pu être encodée.")))
            return
        }
        onFinish?(.success(data))
    }
}
#endif

#if targetEnvironment(simulator)
/// Image de substitution pour le simulateur.
///
/// Elle suit tout le reste du chemin — hachage, pré-filtre, envoi, insertion —
/// pour que la chaîne soit exerçable sans appareil.
///
/// Chaque image est **unique** : l'horodatage et l'objectif y sont dessinés.
/// Sans cela, le SHA-256 serait identique à chaque capture, l'index
/// `proofs_sha_idx` y verrait un doublon et l'anti-triche marquerait
/// `hashDuplicate` sur toutes les preuves de développement — un anti-triche
/// qui fait exactement son travail, sur un faux problème.
enum SimulatorCamera {
    static func image(goalID: UUID) -> Data {
        let size = CGSize(width: 1080, height: 1440)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            UIColor(red: 0.09, green: 0.11, blue: 0.16, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let stamp = """
            PREUVE DE DÉVELOPPEMENT

            \(Date.now.formatted(date: .abbreviated, time: .standard))
            \(goalID.uuidString)
            \(UUID().uuidString)
            """

            let style = NSMutableParagraphStyle()
            style.alignment = .center

            stamp.draw(
                in: CGRect(x: 60, y: size.height / 2 - 200, width: size.width - 120, height: 400),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .medium),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: style,
                ]
            )
        }

        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}
#endif

/// Viseur.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
