import SwiftUI

/// Premier lancement : l'accueil de bienvenue.
///
/// « Commencer » ne demande plus de compte : il ouvre directement la
/// composition d'un premier defi. Rien de ce qui s'y decide ne touche au
/// serveur, et l'ecran d'engagement reclame le compte et la carte au moment
/// de signer — quand l'utilisateur sait enfin ce qu'il achete.
///
/// « Se connecter » reste a part : quelqu'un qui revient n'a pas a recomposer
/// un objectif pour retrouver les siens.
struct OnboardingFlowView: View {
    /// « Commencer » : composer un premier defi, sans compte.
    let onCompose: () -> Void

    @State private var isSigningIn = false

    var body: some View {
        WelcomeView(
            onStart: onCompose,
            onSignIn: { isSigningIn = true }
        )
        .fullScreenCover(isPresented: $isSigningIn) {
            SignInView()
        }
    }
}

#Preview { OnboardingFlowView(onCompose: {}) }
