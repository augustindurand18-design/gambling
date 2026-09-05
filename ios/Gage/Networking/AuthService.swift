import Foundation
import Supabase

/// Connexion par code a usage unique envoye par e-mail.
///
/// Sign in with Apple exige l'entitlement, donc le compte Apple Developer.
/// Le code par e-mail ne depend de rien, marche en simulateur, et cree le
/// profil par le trigger `handle_new_user`. Sign in with Apple viendra
/// s'ajouter le jour ou le compte existera, sans rien changer au reste :
/// c'est la session Supabase qui fait autorite, pas la maniere de l'obtenir.
struct AuthAPI: Sendable {
    static let shared = AuthAPI()
    private let client = SupabaseClientProvider.shared

    /// Envoie un code a six chiffres. Cree le compte si l'adresse est nouvelle.
    func sendCode(to email: String) async throws {
        do {
            try await client.auth.signInWithOTP(email: normalized(email))
        } catch {
            throw Self.mapped(error, fallback: "Impossible d'envoyer le code. Réessaie dans un instant.")
        }
    }

    /// Verifie le code et ouvre la session.
    func verify(code: String, for email: String) async throws {
        do {
            try await client.auth.verifyOTP(
                email: normalized(email),
                token: code.trimmingCharacters(in: .whitespaces),
                type: .email
            )
        } catch {
            throw Self.mapped(error, fallback: "Ce code n'est pas valide ou a expiré.")
        }
    }

    /// Adresse de l'utilisateur connecte, telle qu'il l'a saisie.
    var currentEmail: String? {
        client.auth.currentSession?.user.email
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            throw Self.mapped(error, fallback: "Déconnexion impossible.")
        }
    }

    /// Les adresses sont comparees telles quelles cote serveur : « A@b.fr » et
    /// « a@b.fr » creeraient deux comptes, et l'utilisateur ne retrouverait
    /// plus ses objectifs pour une majuscule.
    private func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Le message technique de Supabase est en anglais et parle de jetons.
    /// On garde la trace complete dans les journaux et on ne montre a
    /// l'utilisateur que ce sur quoi il peut agir.
    private static func mapped(_ error: Error, fallback: String) -> AppError {
        Log.app.error("Authentification: \(error.localizedDescription, privacy: .public)")
        if error is URLError { return .network }
        return .server(message: fallback)
    }
}
