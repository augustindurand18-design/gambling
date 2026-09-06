import Foundation
import Supabase

/// Enregistrement de la carte, et engagement d'une mise.
///
/// La carte ne transite jamais par notre serveur : le PaymentSheet l'envoie
/// directement à Stripe, et il ne nous revient qu'un identifiant de moyen de
/// paiement. C'est ce qui garde le périmètre PCI hors de ce dépôt.
struct PaymentAPI: Sendable {
    static let shared = PaymentAPI()
    private let client = SupabaseClientProvider.shared

    /// Ce qu'il faut pour ouvrir le PaymentSheet.
    struct SetupSession: Decodable, Sendable {
        let setupIntentClientSecret: String
        let ephemeralKey: String
        let customerID: String

        enum CodingKeys: String, CodingKey {
            case setupIntentClientSecret = "setup_intent_client_secret"
            case ephemeralKey = "ephemeral_key"
            case customerID = "customer_id"
        }
    }

    /// Prépare l'enregistrement d'une carte.
    func setupSession() async throws -> SetupSession {
        do {
            _ = try await client.auth.session
        } catch {
            throw AppError.notAuthenticated
        }

        do {
            let response: SetupSession = try await client.functions
                .invoke("stripe-setup-intent", options: FunctionInvokeOptions(body: [String: String]()))
            return response
        } catch {
            Log.payment.error("Préparation de la carte: \(error.localizedDescription, privacy: .public)")
            if error is URLError { throw AppError.network }
            throw AppError.server(message: "Impossible de préparer l'enregistrement de ta carte.")
        }
    }

    /// Engage l'objectif : crée la mise et le consentement, en une transaction.
    ///
    /// C'est `commit_goal` (migration 0017) qui fait tout le travail, et c'est
    /// délibéré. Elle vérifie les plafonds, l'absence de blocage et la
    /// présence d'un moyen de paiement, crée la mise, enregistre le
    /// consentement horodaté et fait passer l'objectif en `committed` — le
    /// tout ou rien. Un `UPDATE` direct laisserait engager de l'argent sans
    /// trace de consentement, et la RLS l'interdit pour cette raison.
    ///
    /// - Returns: l'identifiant de la mise créée.
    @discardableResult
    func commit(
        goalID: UUID,
        amountCents: Int,
        charityID: UUID?,
        consent: ConsentRecord
    ) async throws -> UUID {
        do {
            _ = try await client.auth.session
        } catch {
            throw AppError.notAuthenticated
        }

        do {
            let stakeID: UUID = try await client
                .rpc("commit_goal", params: CommitGoalParams(
                    goalID: goalID,
                    amountCents: amountCents,
                    charityID: charityID,
                    charityBps: BusinessRules.charityBps,
                    termsVersion: AppConfig.termsVersion,
                    termsHash: consent.termsHash,
                    payload: consent,
                    appVersion: AppConfig.appVersion
                ))
                .execute()
                .value

            Log.payment.info("Objectif engagé")
            return stakeID
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Les refus de `commit_goal` doivent se lire, pas se deviner : chacun
    /// correspond à une situation où l'utilisateur peut agir.
    private static func mapped(_ error: Error) -> AppError {
        Log.payment.error("Engagement: \(error.localizedDescription, privacy: .public)")

        if error is URLError { return .network }

        let text = error.localizedDescription
        if text.contains("moyen de paiement") {
            return .server(message: "Enregistre une carte avant d'engager une mise.")
        }
        if text.contains("bloque") || text.contains("blocage") {
            return .server(message: "Un débit est en attente. Régularise-le avant de créer un objectif.")
        }
        if text.contains("plafond par objectif") {
            return .server(message: "Cette mise dépasse ton plafond par objectif.")
        }
        if text.contains("plafond mensuel") {
            return .server(message: "Cette mise dépasse ton plafond du mois.")
        }
        if text.contains("date") || text.contains("passee") {
            return .server(message: "Ce jour est déjà passé.")
        }

        return .server(message: "Ton engagement n'a pas pu être enregistré.")
    }
}

/// Ce que l'utilisateur a vu et accepté, figé au moment du tap.
///
/// Part dans `consents.payload`, table append-only et chaînée. Le jour où
/// quelqu'un conteste un débit devant sa banque, c'est la seule défense :
/// montrer ce qui était affiché à la seconde près.
struct ConsentRecord: Encodable, Sendable {
    let goalTitle: String
    let proofInstruction: String?
    let amountCents: Int
    let charityBps: Int
    let targetDate: String
    let scheduleText: String
    let acceptedAt: Date
    /// Empreinte du texte légal exactement tel qu'affiché.
    let termsHash: String

    enum CodingKeys: String, CodingKey {
        case goalTitle = "goal_title"
        case proofInstruction = "proof_instruction"
        case amountCents = "amount_cents"
        case charityBps = "charity_bps"
        case targetDate = "target_date"
        case scheduleText = "schedule_text"
        case acceptedAt = "accepted_at"
        case termsHash = "terms_hash"
    }
}

private struct CommitGoalParams: Encodable {
    let goalID: UUID
    let amountCents: Int
    let charityID: UUID?
    let charityBps: Int
    let termsVersion: String
    let termsHash: String
    let payload: ConsentRecord
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case goalID = "p_goal_id"
        case amountCents = "p_amount_cents"
        case charityID = "p_charity_id"
        case charityBps = "p_charity_bps"
        case termsVersion = "p_terms_version"
        case termsHash = "p_terms_hash"
        case payload = "p_consent_payload"
        case appVersion = "p_app_version"
    }
}
