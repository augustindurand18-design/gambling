import Foundation
import Supabase

/// Dépôt d'une preuve : le fichier, puis la ligne.
///
/// Deux étapes, dans cet ordre imposé. La RPC `submit_proof` (migration 0026)
/// vérifie que le chemin annoncé est bien dans le dossier de l'utilisateur ;
/// elle ne peut le faire que si le fichier a déjà un chemin.
///
/// Si l'envoi du fichier réussit mais que la RPC refuse — délai écoulé, fenêtre
/// refermée — l'objet reste dans le bucket sans qu'aucune ligne ne le désigne,
/// et le client n'a pas le droit de le supprimer (la policy 0018 n'accorde ni
/// update ni delete). `purge-proofs` devra ramasser ces orphelins : c'est une
/// dette connue, notée dans CLAUDE.md.
struct ProofsAPI: Sendable {
    static let shared = ProofsAPI()
    private let client = SupabaseClientProvider.shared

    /// Taille acceptée par le bucket. Vérifiée ici pour que l'utilisateur lise
    /// une phrase plutôt qu'une erreur de stockage.
    static let maxBytes = 10 * 1024 * 1024

    /// Envoie la photo puis enregistre la preuve.
    ///
    /// - Returns: l'identifiant de la preuve enregistrée.
    @discardableResult
    func submit(
        goalID: UUID,
        jpegData: Data,
        capturedAt: Date,
        precheck: ProofPrecheck,
        exif: ProofExif?
    ) async throws -> UUID {
        guard jpegData.count <= Self.maxBytes else {
            throw AppError.server(message: "La photo est trop lourde.")
        }

        // `session` et non `currentSession` : le second lit un cache synchrone
        // qui peut rendre un jeton périmé sans le dire. Sans jeton valide,
        // l'envoi partirait en tant qu'`anon`, qui n'a aucun droit sur le
        // bucket.
        let userID: UUID
        do {
            userID = try await client.auth.session.user.id
        } catch {
            Log.proof.error("Dépôt de preuve sans session valide")
            throw AppError.notAuthenticated
        }

        // Un identifiant neuf à chaque envoi : aucune policy `update` n'existe
        // sur les objets de stockage, un remplacement échouerait.
        let path = ProofStoragePath.make(userID: userID, goalID: goalID)

        do {
            _ = try await client.storage
                .from("proofs")
                .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg"))
        } catch {
            Log.proof.error("Envoi de la photo: \(error.localizedDescription, privacy: .public)")
            if error is URLError { throw AppError.network }
            throw AppError.server(message: "Ta photo n'a pas pu être envoyée.")
        }

        do {
            let response: UUID = try await client
                .rpc("submit_proof", params: SubmitProofParams(
                    goalID: goalID,
                    storagePath: path,
                    imageSHA256: jpegData.sha256Hex,
                    imageBytes: jpegData.count,
                    capturedAt: capturedAt,
                    precheck: precheck,
                    exif: exif
                ))
                .execute()
                .value

            Log.proof.info("Preuve déposée")
            return response
        } catch {
            throw Self.mapped(error)
        }
    }

    /// La base parle en codes SQL ; l'utilisateur a besoin d'une phrase.
    ///
    /// Le cas qui compte est l'échéance : c'est le seul refus où de l'argent
    /// est en jeu, et il doit se lire sans ambiguïté.
    private static func mapped(_ error: Error) -> AppError {
        Log.proof.error("Dépôt de preuve: \(error.localizedDescription, privacy: .public)")

        if error is URLError { return .network }

        let text = error.localizedDescription
        if text.contains("delai de soumission est ecoule") {
            return .server(message: "Le délai est écoulé. Ta preuve n'a pas pu être prise en compte.")
        }
        if text.contains("fenetre de preuve n'est pas ouverte")
            || text.contains("fenetre de preuve n''est pas ouverte") {
            return .server(message: "La fenêtre de preuve n'est pas ouverte pour cet objectif.")
        }

        return .server(message: "Ta preuve n'a pas pu être enregistrée.")
    }
}

/// Paramètres de la RPC. Les noms doivent correspondre exactement à la
/// signature de `submit_proof`.
private struct SubmitProofParams: Encodable {
    let goalID: UUID
    let storagePath: String
    let imageSHA256: String
    let imageBytes: Int
    let capturedAt: Date
    let precheck: ProofPrecheck
    /// Nul quand l'extraction n'a rien donné. Le serveur lèvera alors son
    /// signal `exif_missing` et la preuve partira en revue humaine — ce qui
    /// est le comportement voulu, pas un contournement à ajouter ici.
    let exif: ProofExif?

    enum CodingKeys: String, CodingKey {
        case goalID = "p_goal_id"
        case storagePath = "p_storage_path"
        case imageSHA256 = "p_image_sha256"
        case imageBytes = "p_image_bytes"
        case capturedAt = "p_captured_at"
        case precheck = "p_ondevice_precheck"
        case exif = "p_exif"
    }
}
