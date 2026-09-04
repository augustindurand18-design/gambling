import SwiftUI

/// Premier lancement : l'accueil de bienvenue, puis la creation du premier
/// objectif.
///
/// Le parcours de creation est le meme que celui lance depuis l'accueil de
/// l'application ; l'onboarding ne fait que l'ouvrir une premiere fois.
struct OnboardingFlowView: View {
    /// Appele quand le premier objectif est engage.
    let onFinished: () -> Void

    @State private var isCreating = false

    var body: some View {
        WelcomeView(
            onStart: { isCreating = true },
            onSignIn: { Log.app.debug("Accueil : Se connecter") }
        )
        .fullScreenCover(isPresented: $isCreating) {
            NewGoalFlowView {
                isCreating = false
                onFinished()
            }
        }
    }
}

#Preview { OnboardingFlowView(onFinished: {}) }
