import SwiftUI

/// Une etape de l'onboarding. Les points en haut d'ecran materialisent la
/// progression ; les trois etapes restantes arriveront avec leurs maquettes.
enum OnboardingStep: Hashable, CaseIterable {
    case stakeAmount
    case goal

    /// Nombre total d'etapes prevues au parcours.
    static let total = 4

    var index: Int {
        switch self {
        case .stakeAmount: 0
        case .goal: 1
        }
    }
}

/// Saisie en cours pendant l'onboarding, avant tout enregistrement serveur.
/// Rien ici n'engage l'utilisateur : le consentement se donne plus tard.
struct OnboardingDraft: Equatable, Sendable {
    var stakeAmountCents: Int = BusinessRules.defaultStakeCents
    var template: GoalTemplate?
}

/// Enchainement des ecrans d'accueil et d'onboarding.
///
/// La pile de navigation et le brouillon vivent ici ; chaque ecran ne connait
/// que sa propre donnee et l'action qui fait avancer le parcours.
struct OnboardingFlowView: View {
    @State private var path: [OnboardingStep] = []
    @State private var draft = OnboardingDraft()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onStart: { path.append(.stakeAmount) },
                onSignIn: { Log.app.debug("Accueil : Se connecter") }
            )
            .navigationDestination(for: OnboardingStep.self) { step in
                switch step {
                case .stakeAmount:
                    StakeAmountView(amountCents: $draft.stakeAmountCents) {
                        path.append(.goal)
                    }

                case .goal:
                    ChooseGoalView(templates: GoalTemplate.onboarding) { template in
                        draft.template = template
                        Log.app.debug("Onboarding : modele choisi \(template.id, privacy: .public)")
                    }
                }
            }
        }
    }
}

#Preview { OnboardingFlowView() }
