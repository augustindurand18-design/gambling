import Foundation

/// Profil utilisateur.
///
/// Les champs sensibles (plafonds, blocage, solde du, moyen de paiement) sont
/// pilotes exclusivement par le serveur : un trigger de base rejette toute
/// tentative de modification depuis le client.
struct Profile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { userID }
    let userID: UUID

    var displayName: String?
    var email: String?

    // Moyen de paiement (metadonnees uniquement, jamais le numero)
    var stripeCustomerID: String?
    var defaultPaymentMethodID: String?
    var pmLast4: String?
    var pmBrand: String?
    var pmExpMonth: Int?
    var pmExpYear: Int?

    // Plafonds acceptes a l'onboarding
    var perGoalCapCents: Int
    var monthlyCapCents: Int

    // Blocage suite a un echec d'encaissement
    var stakeBlockActive: Bool
    var stakeBlockReason: String?
    var stakeBlockSince: Date?
    var outstandingBalanceCents: Int

    var subscriptionTier: String
    var assiduityDiscountActive: Bool
    var onboardingCompletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case email
        case stripeCustomerID = "stripe_customer_id"
        case defaultPaymentMethodID = "default_payment_method_id"
        case pmLast4 = "pm_last4"
        case pmBrand = "pm_brand"
        case pmExpMonth = "pm_exp_month"
        case pmExpYear = "pm_exp_year"
        case perGoalCapCents = "per_goal_cap_cents"
        case monthlyCapCents = "monthly_cap_cents"
        case stakeBlockActive = "stake_block_active"
        case stakeBlockReason = "stake_block_reason"
        case stakeBlockSince = "stake_block_since"
        case outstandingBalanceCents = "outstanding_balance_cents"
        case subscriptionTier = "subscription_tier"
        case assiduityDiscountActive = "assiduity_discount_active"
        case onboardingCompletedAt = "onboarding_completed_at"
    }
}

extension Profile {
    var hasPaymentMethod: Bool { defaultPaymentMethodID != nil }
    var canCreateGoals: Bool { !stakeBlockActive && hasPaymentMethod }

    /// Contexte de transition derive du profil, complete ensuite par l'objectif.
    func transitionContext(monthCommittedCents: Int = 0) -> GoalTransitionContext {
        GoalTransitionContext(
            isBlockedForPayment: stakeBlockActive,
            outstandingBalanceCents: outstandingBalanceCents,
            hasPaymentMethod: hasPaymentMethod,
            perGoalCapCents: perGoalCapCents,
            monthlyCapCents: monthlyCapCents,
            monthCommittedCents: monthCommittedCents
        )
    }
}
