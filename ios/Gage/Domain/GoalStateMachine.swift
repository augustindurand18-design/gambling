import Foundation

/// Machine a etats d'un objectif.
///
/// Fonction pure, sans effet de bord : elle sert a piloter l'interface
/// (qu'est-ce que l'utilisateur peut faire maintenant ?) et a appliquer des
/// mises a jour optimistes. Les transitions reelles sont executees et
/// validees cote serveur — voir `app.goal_state_allowed` en base.
///
/// Toute modification ici doit etre repercutee dans
/// `supabase/migrations/0015_state_machine_trigger.sql`, et inversement.
/// `GoalStateMachineTests` verrouille cette correspondance.
enum GoalStateMachine {

    /// Table de verite des transitions legales. Strictement identique a celle
    /// de la base.
    static let allowedTransitions: [GoalState: Set<GoalState>] = [
        // Engagement
        .draft: [.committed],

        // Ouverture de la fenetre de preuve. Le rejet direct est un filet de
        // securite : fenetre jamais ouverte et echeance depassee.
        .committed: [.proofWindowOpen, .rejected],

        // Soumission, ou echeance depassee sans preuve.
        .proofWindowOpen: [.proofSubmitted, .rejected],

        // Rejet immediat possible : preuve hors fenetre, image deja vue.
        .proofSubmitted: [.aiVerifying, .rejected],

        // Toute erreur de verification part en revue humaine, jamais en rejet
        // automatique : on ne debite pas sur un doute technique.
        .aiVerifying: [.validated, .rejected, .humanReview],

        // Echantillon aleatoire anti-fraude sur un verdict favorable.
        .validated: [.closedKept, .humanReview],

        // Contestation, ou expiration de la fenetre de contestation.
        .rejected: [.humanReview, .closedFailed],

        // Decision du reviewer, definitive.
        .humanReview: [.closedKept, .closedFailed],

        // Encaissement
        .closedFailed: [.chargePending],
        .chargePending: [.chargeOk, .chargeFailed],

        // Relance apres mise a jour de la carte, ou reussite d'un retry Stripe.
        .chargeFailed: [.chargePending, .chargeOk],

        // Terminaux
        .closedKept: [],
        .chargeOk: []
    ]

    /// Etats atteignables depuis `state`.
    static func allowedTransitions(from state: GoalState) -> Set<GoalState> {
        allowedTransitions[state] ?? []
    }

    /// La transition est-elle legale au regard de la table de verite ?
    ///
    /// Ne verifie que la structure du cycle de vie. Les regles metier
    /// (plafonds, blocage paiement, echeances) sont evaluees par
    /// ``canTransition(from:to:context:)``.
    static func isStructurallyAllowed(from: GoalState, to: GoalState) -> Bool {
        allowedTransitions(from: from).contains(to)
    }

    /// Verifie la transition, structure et regles metier comprises.
    static func canTransition(
        from: GoalState,
        to: GoalState,
        context: GoalTransitionContext
    ) -> Result<Void, GoalTransitionError> {
        guard isStructurallyAllowed(from: from, to: to) else {
            return .failure(.illegalTransition(from: from, to: to))
        }

        switch (from, to) {
        case (.draft, .committed):
            return validateCommit(context)

        case (.proofWindowOpen, .proofSubmitted):
            guard let deadline = context.proofDeadlineAt else {
                return .failure(.missingDeadline)
            }
            guard context.now <= deadline else {
                return .failure(.proofWindowClosed(deadline: deadline))
            }
            return .success(())

        case (.rejected, .humanReview):
            guard let deadline = context.disputeDeadlineAt else {
                return .failure(.missingDeadline)
            }
            guard context.now <= deadline else {
                return .failure(.disputeWindowClosed(deadline: deadline))
            }
            return .success(())

        default:
            return .success(())
        }
    }

    private static func validateCommit(
        _ context: GoalTransitionContext
    ) -> Result<Void, GoalTransitionError> {
        // Un incident de paiement non regle gele la creation de nouveaux
        // engagements. Les objectifs deja en cours, eux, se poursuivent.
        guard !context.isBlockedForPayment else {
            return .failure(.blockedForPayment(
                outstandingBalanceCents: context.outstandingBalanceCents
            ))
        }

        guard context.hasPaymentMethod else {
            return .failure(.noPaymentMethod)
        }

        guard let amount = context.stakeAmountCents, amount > 0 else {
            return .failure(.invalidStakeAmount)
        }

        guard amount <= context.perGoalCapCents else {
            return .failure(.exceedsPerGoalCap(
                amountCents: amount,
                capCents: context.perGoalCapCents
            ))
        }

        let projected = context.monthCommittedCents + amount
        guard projected <= context.monthlyCapCents else {
            return .failure(.exceedsMonthlyCap(
                projectedCents: projected,
                capCents: context.monthlyCapCents
            ))
        }

        return .success(())
    }
}

/// Etat courant necessaire pour evaluer une transition.
struct GoalTransitionContext: Sendable {
    var now: Date = .now

    // Profil
    var isBlockedForPayment: Bool = false
    var outstandingBalanceCents: Int = 0
    var hasPaymentMethod: Bool = false
    var perGoalCapCents: Int = 3_000
    var monthlyCapCents: Int = 15_000
    var monthCommittedCents: Int = 0

    // Objectif
    var stakeAmountCents: Int?
    var proofDeadlineAt: Date?
    var disputeDeadlineAt: Date?
}

enum GoalTransitionError: Error, Equatable, Sendable {
    case illegalTransition(from: GoalState, to: GoalState)
    case blockedForPayment(outstandingBalanceCents: Int)
    case noPaymentMethod
    case invalidStakeAmount
    case exceedsPerGoalCap(amountCents: Int, capCents: Int)
    case exceedsMonthlyCap(projectedCents: Int, capCents: Int)
    case proofWindowClosed(deadline: Date)
    case disputeWindowClosed(deadline: Date)
    case missingDeadline
}

extension GoalTransitionError {
    /// Message destine a l'utilisateur. Volontairement factuel et non
    /// culpabilisant : le produit vend la confiance.
    var localizedMessage: String {
        switch self {
        case .illegalTransition:
            "Cette action n'est pas possible à ce stade."

        case .blockedForPayment(let balance):
            "Une mise de \(Self.euros(balance)) reste à régler. "
            + "Mets ta carte à jour pour engager un nouvel objectif."

        case .noPaymentMethod:
            "Ajoute une carte avant d'engager un objectif."

        case .invalidStakeAmount:
            "Le montant engagé doit être supérieur à zéro."

        case .exceedsPerGoalCap(_, let cap):
            "Le montant dépasse ton plafond par objectif (\(Self.euros(cap))). "
            + "Tu peux le modifier dans tes réglages."

        case .exceedsMonthlyCap(_, let cap):
            "Tu atteindrais ton plafond mensuel de \(Self.euros(cap))."

        case .proofWindowClosed:
            "Le délai pour envoyer ta preuve est dépassé."

        case .disputeWindowClosed:
            "Le délai de contestation est dépassé."

        case .missingDeadline:
            "Échéance introuvable pour cet objectif."
        }
    }

    private static func euros(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "fr_FR")
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100) €"
    }
}
