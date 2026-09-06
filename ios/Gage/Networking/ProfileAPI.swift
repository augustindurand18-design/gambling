import Foundation
import Supabase

/// Lecture du profil et choix de l'association.
///
/// Le profil porte tout ce qui conditionne un engagement : moyen de paiement,
/// plafonds, blocage éventuel. L'application le lit pour savoir ce qu'elle
/// peut proposer — mais c'est `commit_goal` qui tranche, côté base. Un
/// contrôle côté client est une politesse, pas une garantie.
struct ProfileAPI: Sendable {
    static let shared = ProfileAPI()
    private let client = SupabaseClientProvider.shared

    private static let columns = """
    user_id,pm_last4,pm_brand,per_goal_cap_cents,monthly_cap_cents,\
    stake_block_active,stake_block_reason,outstanding_balance_cents,\
    default_charity_id,default_payment_method_id
    """

    func load() async throws -> AccountState {
        do {
            _ = try await client.auth.session
        } catch {
            throw AppError.notAuthenticated
        }

        do {
            return try await client
                .from("profiles")
                .select(Self.columns)
                .single()
                .execute()
                .value
        } catch {
            Log.payment.error("Chargement du profil: \(error.localizedDescription, privacy: .public)")
            if error is URLError { throw AppError.network }
            if error is DecodingError { throw AppError.decoding }
            throw AppError.server(message: "Impossible de charger ton compte.")
        }
    }

    /// Associations proposées. Seules les actives sont visibles (policy 0016).
    func charities() async throws -> [Charity] {
        do {
            return try await client
                .from("charities")
                .select("id,slug,name,description,website_url")
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            if error is URLError { throw AppError.network }
            throw AppError.server(message: "Impossible de charger les associations.")
        }
    }

    /// Enregistre l'association vers laquelle ira la part reversée.
    ///
    /// Les engagements déjà pris ne bougent pas : `commit_goal` recopie la
    /// valeur sur l'objectif au moment de l'engagement, où elle se fige.
    func chooseCharity(_ charityID: UUID) async throws {
        let userID: UUID
        do {
            userID = try await client.auth.session.user.id
        } catch {
            throw AppError.notAuthenticated
        }

        do {
            try await client
                .from("profiles")
                .update(["default_charity_id": charityID])
                .eq("user_id", value: userID)
                .execute()
        } catch {
            if error is URLError { throw AppError.network }
            throw AppError.server(message: "Ton choix n'a pas pu être enregistré.")
        }
    }
}

/// Ce que l'application a besoin de savoir sur le compte avant d'engager.
struct AccountState: Decodable, Sendable {
    let userID: UUID
    let pmLast4: String?
    let pmBrand: String?
    let perGoalCapCents: Int
    let monthlyCapCents: Int
    let stakeBlockActive: Bool
    let stakeBlockReason: String?
    let outstandingBalanceCents: Int
    let defaultCharityID: UUID?
    let defaultPaymentMethodID: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case pmLast4 = "pm_last4"
        case pmBrand = "pm_brand"
        case perGoalCapCents = "per_goal_cap_cents"
        case monthlyCapCents = "monthly_cap_cents"
        case stakeBlockActive = "stake_block_active"
        case stakeBlockReason = "stake_block_reason"
        case outstandingBalanceCents = "outstanding_balance_cents"
        case defaultCharityID = "default_charity_id"
        case defaultPaymentMethodID = "default_payment_method_id"
    }

    /// Le compte est-il prêt à engager de l'argent ?
    var canCommit: Bool {
        defaultPaymentMethodID != nil && !stakeBlockActive
    }

    /// Une carte est-elle enregistrée ?
    ///
    /// C'est `default_payment_method_id` qui fait foi, jamais `pm_last4` :
    /// le premier est ce qui permet de débiter, le second n'est qu'un
    /// ornement d'affichage, écrit par le webhook après coup. Les deux
    /// peuvent diverger — une carte enregistrée avant que le webhook ne
    /// fonctionne a bien un moyen de paiement et pas de quatre chiffres — et
    /// l'écran annonçait alors « À enregistrer » à quelqu'un qui pouvait
    /// engager de l'argent.
    var hasCard: Bool { defaultPaymentMethodID != nil }

    /// Ce que l'écran affiche pour la carte.
    ///
    /// Les quatre chiffres quand on les connaît, sinon le seul fait qu'une
    /// carte existe — ce qui est la question à laquelle l'utilisateur veut
    /// une réponse.
    var cardLabel: String {
        guard hasCard else { return "À enregistrer" }
        guard let last4 = pmLast4 else { return "Carte enregistrée" }
        return "\(pmBrand?.capitalized ?? "Carte") •••• \(last4)"
    }

    /// Ce qui manque, dit à l'utilisateur.
    var blocker: String? {
        if stakeBlockActive {
            return outstandingBalanceCents > 0
                ? "Un débit de \(Money.format(cents: outstandingBalanceCents)) n'a pas pu aboutir. "
                    + "Mets ta carte à jour pour reprendre."
                : "Ton compte est en attente de régularisation."
        }
        if defaultPaymentMethodID == nil {
            return "Enregistre une carte pour pouvoir engager une mise."
        }
        return nil
    }
}
