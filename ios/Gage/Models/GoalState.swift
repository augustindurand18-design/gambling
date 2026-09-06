import Foundation

/// Cycle de vie d'un objectif.
///
/// Ce type est le miroir exact de l'enum Postgres `goal_state` et de la table
/// de verite `app.goal_state_allowed`. Les deux doivent evoluer ensemble :
/// la base est l'autorite, ce type sert au pilotage de l'interface et aux
/// mises a jour optimistes.
///
/// - SeeAlso: `supabase/migrations/0015_state_machine_trigger.sql`
enum GoalState: String, Codable, CaseIterable, Sendable {
    /// En cours de composition. Aucun engagement, aucun argent en jeu.
    case draft

    /// Mise et consentement enregistres, fenetre de preuve planifiee.
    case committed

    /// La notification est partie : l'utilisateur peut soumettre sa preuve.
    case proofWindowOpen = "proof_window_open"

    /// Photo deposee, metadonnees serveur posees.
    case proofSubmitted = "proof_submitted"

    /// Verification en cours.
    case aiVerifying = "ai_verifying"

    /// Verdict favorable.
    case validated

    /// Verdict defavorable. Contestable jusqu'a `disputeDeadlineAt`.
    case rejected

    /// En file de revue manuelle (verdict incertain, contestation, ou
    /// echantillon aleatoire anti-fraude).
    case humanReview = "human_review"

    /// Terminal : objectif tenu, rien n'est debite.
    case closedKept = "closed_kept"

    /// Echec confirme et non contestable. Le debit va etre declenche.
    case closedFailed = "closed_failed"

    /// Debit en cours cote Stripe.
    case chargePending = "charge_pending"

    /// Terminal : mise encaissee.
    case chargeOk = "charge_ok"

    /// Terminal bloquant : le debit a echoue. Une somme reste due et la
    /// creation de nouveaux objectifs est gelee jusqu'a regularisation.
    case chargeFailed = "charge_failed"
}

extension GoalState {
    /// Etats depuis lesquels plus aucune transition n'est possible.
    var isTerminal: Bool {
        switch self {
        case .closedKept, .chargeOk: true
        default: false
        }
    }

    /// L'objectif est-il encore en cours de resolution ?
    var isActive: Bool {
        switch self {
        case .committed, .proofWindowOpen, .proofSubmitted, .aiVerifying,
             .validated, .rejected, .humanReview:
            true
        default:
            false
        }
    }

    /// L'objectif appartient-il a l'historique ?
    ///
    /// Un brouillon n'y figure pas : il n'a jamais rien engage, et le montrer
    /// parmi des promesses tenues ou perdues raconterait une histoire fausse.
    var isPast: Bool {
        !isActive && self != .draft
    }

    /// L'utilisateur a-t-il de l'argent engage a cet instant ?
    var hasMoneyAtRisk: Bool {
        isActive || self == .closedFailed || self == .chargePending || self == .chargeFailed
    }

    /// L'utilisateur peut-il agir maintenant ?
    var awaitsUserAction: Bool {
        switch self {
        case .proofWindowOpen, .rejected: true
        default: false
        }
    }

    /// La mise a-t-elle ete perdue ?
    ///
    /// `chargeOk` en fait partie : un debit reussi est une reussite pour le
    /// systeme, jamais pour l'utilisateur. Le confondre avec un objectif tenu
    /// lui montrerait en vert le moment ou il a paye.
    var hasLostStake: Bool {
        switch self {
        case .closedFailed, .chargePending, .chargeOk, .chargeFailed: true
        default: false
        }
    }

    /// Libelle destine a l'utilisateur.
    var localizedLabel: String {
        switch self {
        case .draft: "Brouillon"
        case .committed: "Engagé"
        case .proofWindowOpen: "Preuve attendue"
        case .proofSubmitted: "Preuve envoyée"
        case .aiVerifying: "Vérification en cours"
        case .validated: "Validé"
        case .rejected: "Refusé"
        case .humanReview: "En cours d'examen"
        case .closedKept: "Tenu"
        case .closedFailed: "Non tenu"
        case .chargePending: "Débit en cours"
        case .chargeOk: "Mise débitée"
        case .chargeFailed: "Paiement en échec"
        }
    }
}
