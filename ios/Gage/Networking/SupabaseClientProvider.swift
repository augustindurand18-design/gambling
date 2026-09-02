import Foundation
import Supabase

/// Client Supabase partage.
///
/// L'isolation des donnees repose entierement sur les policies RLS cote base :
/// la cle anon est publique par conception et ne donne acces a rien d'autre
/// qu'aux lignes de l'utilisateur authentifie.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseAnonKey
    )
}

/// Erreurs remontees a l'interface.
enum AppError: LocalizedError, Equatable {
    case notAuthenticated
    case transition(GoalTransitionError)
    case server(message: String)
    case network
    case decoding

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Tu dois être connecté pour effectuer cette action."
        case .transition(let error):
            error.localizedMessage
        case .server(let message):
            message
        case .network:
            "Connexion impossible. Vérifie ton réseau et réessaie."
        case .decoding:
            "Réponse inattendue du serveur."
        }
    }
}

/// Accès minimal aux appareils enregistrés.
struct DevicesAPI {
    static let shared = DevicesAPI()
    private let client = SupabaseClientProvider.shared

    func upsert(_ device: DeviceRegistration) async throws {
        guard let userID = client.auth.currentSession?.user.id else {
            throw AppError.notAuthenticated
        }

        struct Row: Encodable {
            let user_id: UUID
            let apns_token: String
            let env: String
            let bundle_id: String?
            let app_version: String
            let os_version: String
            let model: String
            let revoked: Bool
        }

        try await client
            .from("devices")
            .upsert(
                Row(
                    user_id: userID,
                    apns_token: device.apnsToken,
                    env: device.env,
                    bundle_id: device.bundleID,
                    app_version: device.appVersion,
                    os_version: device.osVersion,
                    model: device.model,
                    revoked: false
                ),
                onConflict: "user_id,apns_token"
            )
            .execute()
    }
}
