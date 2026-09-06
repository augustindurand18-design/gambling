import Testing
@testable import Gage

/// Ce que chaque etat dit de l'argent.
///
/// L'ecran se colore et affiche un montant a partir de ces reponses. Une
/// erreur ici ne casse rien, ne fait echouer aucune compilation, et raconte a
/// quelqu'un une histoire fausse sur son propre argent — c'est arrive :
/// « Mise debitee » s'affichait en vert, parmi les objectifs tenus.
struct GoalStateMoneyTests {

    @Test("Un debit reussi est une perte pour l'utilisateur")
    func chargeOkIsALoss() {
        // `charge_ok` est une reussite pour le systeme, jamais pour
        // l'utilisateur : c'est l'instant ou il a paye.
        #expect(GoalState.chargeOk.hasLostStake)
        #expect(GoalState.chargeOk.localizedLabel == "Mise débitée")
    }

    @Test("Tous les etats d'echec comptent comme une mise perdue")
    func lostStates() {
        for state in [GoalState.closedFailed, .chargePending, .chargeOk, .chargeFailed] {
            #expect(state.hasLostStake, "\(state.rawValue) devrait compter comme une perte")
        }
    }

    @Test("Un objectif tenu n'a rien perdu")
    func keptLosesNothing() {
        #expect(!GoalState.closedKept.hasLostStake)
        #expect(GoalState.closedKept.localizedLabel == "Tenu")
    }

    @Test("Un objectif encore en cours n'a rien perdu")
    func pendingLosesNothing() {
        // Tant que rien n'est joue, l'ecran montre ce qui est en jeu, pas une
        // perte : annoncer une somme perdue avant l'heure serait faux.
        for state in [GoalState.draft, .committed, .proofWindowOpen,
                      .proofSubmitted, .aiVerifying, .validated,
                      .rejected, .humanReview] {
            #expect(!state.hasLostStake, "\(state.rawValue) ne devrait rien avoir perdu")
        }
    }

    @Test("Un objectif refusé n'a pas encore perdu sa mise")
    func rejectedHasNotPaidYet() {
        // Le refus precede le debit : la mise n'est prelevee qu'apres la
        // cloture. L'afficher comme deja perdue annoncerait un prelevement
        // qui n'a pas eu lieu.
        #expect(!GoalState.rejected.hasLostStake)
        #expect(GoalState.rejected.localizedLabel == "Refusé")
    }
}
