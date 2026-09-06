import CryptoKit
import Foundation

/// Preuve déposée pour un objectif.
///
/// L'application n'en écrit jamais le verdict : `ai_verdict`, `final_verdict`
/// et tout ce qui les accompagne sont posés par le serveur seul. Ce modèle ne
/// porte donc que ce que l'appareil produit.
struct Proof: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID
    let storagePath: String?
    let imageSHA256: String
    let imageBytes: Int?
    let capturedAt: Date?
    let serverReceivedAt: Date
    let finalVerdict: String?

    enum CodingKeys: String, CodingKey {
        case id
        case goalID = "goal_id"
        case userID = "user_id"
        case storagePath = "storage_path"
        case imageSHA256 = "image_sha256"
        case imageBytes = "image_bytes"
        case capturedAt = "captured_at"
        case serverReceivedAt = "server_received_at"
        case finalVerdict = "final_verdict"
    }
}

/// Emplacement d'une preuve dans le bucket `proofs`.
///
/// La forme n'est pas libre : la policy de stockage (migration 0018) exige que
/// le premier segment soit l'identifiant de l'utilisateur, et `submit_proof`
/// (0026) revérifie le préfixe complet avant d'enregistrer quoi que ce soit.
/// Une ligne de `proofs` ne doit jamais pouvoir désigner le fichier de
/// quelqu'un d'autre.
enum ProofStoragePath {
    /// `{user_id}/{goal_id}/{uuid}.jpg`
    ///
    /// Sans le nom du bucket : `storage.from("proofs")` le porte déjà, et
    /// l'inclure ici décalerait tous les segments d'un cran, faisant échouer
    /// la policy sur un message illisible.
    ///
    /// **En minuscules.** `UUID.uuidString` rend l'identifiant en majuscules,
    /// `auth.uid()::text` le rend en minuscules, et la policy de stockage
    /// compare les deux chaînes littéralement : sans cette conversion, tout
    /// envoi est refusé. `submit_proof` revérifie le même préfixe, donc le
    /// refus arriverait deux fois plutôt que d'être rattrapé.
    static func make(userID: UUID, goalID: UUID, fileID: UUID = UUID()) -> String {
        "\(userID.uuidString.lowercased())/\(goalID.uuidString.lowercased())/\(fileID.uuidString.lowercased()).jpg"
    }
}

extension Data {
    /// Empreinte des octets tels qu'ils seront envoyés.
    ///
    /// Le hachage porte sur le JPEG final, jamais sur l'image en mémoire : le
    /// serveur compare cette valeur à ce qu'il reçoit, et l'encodage n'est pas
    /// reproductible à l'octet près d'une exécution à l'autre.
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
