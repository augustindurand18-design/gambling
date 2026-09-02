import Testing
import Foundation
@testable import Gage

@Suite("Machine a etats d'un objectif")
struct GoalStateMachineTests {

    // MARK: - Structure du cycle de vie

    @Test("Chaque etat a une entree dans la table de verite")
    func everyStateIsCovered() {
        for state in GoalState.allCases {
            #expect(
                GoalStateMachine.allowedTransitions[state] != nil,
                "\(state.rawValue) n'a pas d'entree : oubli lors d'un ajout d'etat ?"
            )
        }
    }

    @Test("Les etats terminaux n'ont aucune transition sortante")
    func terminalStatesAreDeadEnds() {
        for state in GoalState.allCases where state.isTerminal {
            #expect(
                GoalStateMachine.allowedTransitions(from: state).isEmpty,
                "\(state.rawValue) est terminal mais autorise encore des transitions"
            )
        }
    }

    @Test("Tout etat non terminal reste atteignable depuis draft")
    func allStatesReachableFromDraft() {
        var reached: Set<GoalState> = [.draft]
        var frontier: [GoalState] = [.draft]

        while let current = frontier.popLast() {
            for next in GoalStateMachine.allowedTransitions(from: current)
            where !reached.contains(next) {
                reached.insert(next)
                frontier.append(next)
            }
        }

        for state in GoalState.allCases {
            #expect(reached.contains(state), "\(state.rawValue) est inatteignable")
        }
    }

    // MARK: - Garde-fous critiques
    //
    // Ces tests protegent l'utilisateur : aucun chemin ne doit permettre
    // de debiter sans etre passe par une verification et par la fenetre
    // de contestation.

    @Test("On ne debite jamais sans verification prealable")
    func noChargeWithoutVerification() {
        let forbidden: [(GoalState, GoalState)] = [
            (.draft, .chargeOk),
            (.draft, .closedFailed),
            (.committed, .chargePending),
            (.committed, .closedFailed),
            (.proofWindowOpen, .closedFailed),
            (.rejected, .chargePending)
        ]

        for (from, to) in forbidden {
            #expect(
                !GoalStateMachine.isStructurallyAllowed(from: from, to: to),
                "\(from.rawValue) -> \(to.rawValue) ne doit pas etre possible"
            )
        }
    }

    @Test("Un echec ne peut etre encaisse qu'apres closedFailed")
    func chargeOnlyAfterClosedFailed() {
        let predecessors = GoalState.allCases.filter {
            GoalStateMachine.allowedTransitions(from: $0).contains(.chargePending)
        }
        #expect(Set(predecessors) == [.closedFailed, .chargeFailed])
    }

    @Test("Un rejet ne peut pas devenir un succes sans passer par la revue humaine")
    func rejectionRequiresHumanReviewToBeOverturned() {
        #expect(!GoalStateMachine.isStructurallyAllowed(from: .rejected, to: .validated))
        #expect(!GoalStateMachine.isStructurallyAllowed(from: .rejected, to: .closedKept))
        #expect(GoalStateMachine.isStructurallyAllowed(from: .rejected, to: .humanReview))
        #expect(GoalStateMachine.isStructurallyAllowed(from: .humanReview, to: .closedKept))
    }

    @Test("Une verification incertaine peut toujours partir en revue humaine")
    func verificationCanAlwaysEscalate() {
        #expect(GoalStateMachine.isStructurallyAllowed(from: .aiVerifying, to: .humanReview))
    }

    // MARK: - Regles metier a l'engagement

    private func context(
        blocked: Bool = false,
        balance: Int = 0,
        hasCard: Bool = true,
        amount: Int? = 1_000,
        perGoalCap: Int = 3_000,
        monthlyCap: Int = 15_000,
        monthCommitted: Int = 0
    ) -> GoalTransitionContext {
        GoalTransitionContext(
            isBlockedForPayment: blocked,
            outstandingBalanceCents: balance,
            hasPaymentMethod: hasCard,
            perGoalCapCents: perGoalCap,
            monthlyCapCents: monthlyCap,
            monthCommittedCents: monthCommitted,
            stakeAmountCents: amount
        )
    }

    @Test("Un engagement conforme est accepte")
    func validCommitSucceeds() {
        let result = GoalStateMachine.canTransition(
            from: .draft, to: .committed, context: context()
        )
        #expect(result == .success(()))
    }

    @Test("Un incident de paiement gele la creation de nouveaux objectifs")
    func paymentBlockPreventsCommit() {
        let result = GoalStateMachine.canTransition(
            from: .draft, to: .committed,
            context: context(blocked: true, balance: 2_000)
        )
        #expect(result == .failure(.blockedForPayment(outstandingBalanceCents: 2_000)))
    }

    @Test("Pas d'engagement sans moyen de paiement")
    func cardRequired() {
        let result = GoalStateMachine.canTransition(
            from: .draft, to: .committed, context: context(hasCard: false)
        )
        #expect(result == .failure(.noPaymentMethod))
    }

    @Test("Le plafond par objectif est applique")
    func perGoalCapEnforced() {
        let result = GoalStateMachine.canTransition(
            from: .draft, to: .committed,
            context: context(amount: 5_000, perGoalCap: 3_000)
        )
        #expect(result == .failure(.exceedsPerGoalCap(amountCents: 5_000, capCents: 3_000)))
    }

    @Test("Le plafond mensuel tient compte du deja-engage")
    func monthlyCapEnforced() {
        let result = GoalStateMachine.canTransition(
            from: .draft, to: .committed,
            context: context(amount: 2_000, monthlyCap: 15_000, monthCommitted: 14_000)
        )
        #expect(result == .failure(.exceedsMonthlyCap(projectedCents: 16_000, capCents: 15_000)))
    }

    @Test("Une mise nulle ou negative est refusee", arguments: [0, -100])
    func rejectsNonPositiveStake(amount: Int) {
        let result = GoalStateMachine.canTransition(
            from: .draft, to: .committed, context: context(amount: amount)
        )
        #expect(result == .failure(.invalidStakeAmount))
    }

    // MARK: - Echeances

    @Test("Une preuve envoyee apres l'echeance est refusee")
    func lateProofRejected() {
        let deadline = Date.now.addingTimeInterval(-60)
        var ctx = context()
        ctx.proofDeadlineAt = deadline

        let result = GoalStateMachine.canTransition(
            from: .proofWindowOpen, to: .proofSubmitted, context: ctx
        )
        #expect(result == .failure(.proofWindowClosed(deadline: deadline)))
    }

    @Test("Une preuve envoyee dans les temps est acceptee")
    func timelyProofAccepted() {
        var ctx = context()
        ctx.proofDeadlineAt = Date.now.addingTimeInterval(600)

        let result = GoalStateMachine.canTransition(
            from: .proofWindowOpen, to: .proofSubmitted, context: ctx
        )
        #expect(result == .success(()))
    }

    @Test("Une contestation hors delai est refusee")
    func lateDisputeRejected() {
        let deadline = Date.now.addingTimeInterval(-3_600)
        var ctx = context()
        ctx.disputeDeadlineAt = deadline

        let result = GoalStateMachine.canTransition(
            from: .rejected, to: .humanReview, context: ctx
        )
        #expect(result == .failure(.disputeWindowClosed(deadline: deadline)))
    }

    // MARK: - Proprietes d'affichage

    @Test("Les etats a risque financier sont correctement identifies")
    func moneyAtRiskStates() {
        #expect(!GoalState.draft.hasMoneyAtRisk)
        #expect(GoalState.committed.hasMoneyAtRisk)
        #expect(GoalState.chargeFailed.hasMoneyAtRisk)
        #expect(!GoalState.closedKept.hasMoneyAtRisk)
        #expect(!GoalState.chargeOk.hasMoneyAtRisk)
    }

    @Test("Les etats en attente d'action utilisateur sont correctement identifies")
    func userActionStates() {
        #expect(GoalState.proofWindowOpen.awaitsUserAction)
        #expect(GoalState.rejected.awaitsUserAction)
        #expect(!GoalState.aiVerifying.awaitsUserAction)
        #expect(!GoalState.closedKept.awaitsUserAction)
    }
}

extension Result where Success == Void, Failure == GoalTransitionError {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.success, .success): true
        case (.failure(let l), .failure(let r)): l == r
        default: false
        }
    }
}
