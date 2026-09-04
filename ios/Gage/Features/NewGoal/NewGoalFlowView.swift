import SwiftUI

/// Une etape de la creation d'un objectif. Les points en haut d'ecran
/// materialisent la progression.
enum NewGoalStep: Hashable, CaseIterable {
    case stakeAmount
    case goal
    case proof
    case commitment

    static let total = NewGoalStep.allCases.count

    var index: Int {
        switch self {
        case .stakeAmount: 0
        case .goal: 1
        case .proof: 2
        case .commitment: 3
        }
    }
}

/// Saisie en cours, avant tout enregistrement serveur. Rien ici n'engage
/// l'utilisateur tant que l'ecran d'engagement n'a pas recueilli sa signature.
struct GoalDraft: Equatable, Sendable {
    var stakeAmountCents: Int = BusinessRules.defaultStakeCents
    var composition = GoalComposition()
}

/// Parcours complet de creation d'un objectif : mise, composition, preuve,
/// engagement.
///
/// Presente en plein ecran, aussi bien au premier lancement qu'ensuite depuis
/// l'accueil. Le premier ecran a donc un retour qui referme le parcours au
/// lieu de depiler — c'est `dismiss()` qui fait les deux selon le contexte.
struct NewGoalFlowView: View {
    /// Appele quand l'utilisateur a signe son engagement.
    let onCommitted: () -> Void

    @State private var path: [NewGoalStep] = []
    @State private var draft = GoalDraft()

    var body: some View {
        NavigationStack(path: $path) {
            StakeAmountView(amountCents: $draft.stakeAmountCents) {
                path.append(.goal)
            }
            .navigationDestination(for: NewGoalStep.self) { step in
                switch step {
                case .stakeAmount:
                    // Jamais empile : la mise est la racine du parcours.
                    EmptyView()

                case .goal:
                    ComposeGoalView(composition: $draft.composition) {
                        path.append(.proof)
                    }

                case .proof:
                    ChooseProofView(composition: $draft.composition) {
                        path.append(.commitment)
                    }

                case .commitment:
                    CommitmentView(draft: $draft, onCommitted: onCommitted)
                }
            }
        }
    }
}

#Preview { NewGoalFlowView(onCommitted: {}) }
