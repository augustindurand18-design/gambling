import SwiftUI

/// Une etape de la creation d'un objectif. Les points en haut d'ecran
/// materialisent la progression.
///
/// L'ordre suit la logique de l'engagement : on decide d'abord ce qu'on
/// promet, ensuite comment on le prouvera, et seulement alors combien on
/// mise. Poser le montant en premier ferait choisir un objectif en fonction
/// de la somme, alors que c'est la somme qui doit s'ajuster a la promesse.
enum NewGoalStep: Hashable, CaseIterable {
    case category
    case variant
    case plan
    case proof
    case stake
    case commitment

    /// Une famille qui n'a qu'une declinaison saute l'etape correspondante :
    /// le parcours ne compte alors que cinq points de progression.
    static func total(skippingVariant: Bool) -> Int {
        skippingVariant ? allCases.count - 1 : allCases.count
    }

    func index(skippingVariant: Bool) -> Int {
        guard skippingVariant, self != .category else { return rank }
        return rank - 1
    }

    private var rank: Int {
        switch self {
        case .category: 0
        case .variant: 1
        case .plan: 2
        case .proof: 3
        case .stake: 4
        case .commitment: 5
        }
    }
}

/// Saisie en cours, avant tout enregistrement serveur. Rien ici n'engage
/// l'utilisateur tant que l'ecran d'engagement n'a pas recueilli sa signature.
struct GoalDraft: Equatable, Sendable {
    var stakeAmountCents: Int = BusinessRules.defaultStakeCents
    var plan = GoalPlan()
}

/// Parcours complet de creation d'un objectif : objectif, preuve, mise,
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
            ChooseCategoryView(plan: $draft.plan) {
                // La declinaison est deja retenue quand la famille n'en a
                // qu'une : son ecran n'aurait rien a faire choisir.
                path.append(draft.plan.skipsVariantStep ? .plan : .variant)
            }
            .navigationDestination(for: NewGoalStep.self) { step in
                switch step {
                case .category:
                    // Jamais empile : la liste des familles est la racine.
                    EmptyView()

                case .variant:
                    ChooseVariantView(plan: $draft.plan) {
                        path.append(.plan)
                    }

                case .plan:
                    PlanWeekView(plan: $draft.plan) {
                        path.append(.proof)
                    }

                case .proof:
                    ChooseProofView(plan: $draft.plan) {
                        path.append(.stake)
                    }

                case .stake:
                    StakeAmountView(
                        amountCents: $draft.stakeAmountCents,
                        plan: $draft.plan
                    ) {
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
