import SwiftUI

/// Premier lancement : l'accueil de bienvenue, puis la connexion.
///
/// Les deux boutons menent au meme ecran. Creer un compte et en retrouver un
/// sont le meme appel cote serveur, et l'utilisateur n'a pas a se souvenir
/// s'il est deja venu.
///
/// Le premier objectif ne se compose plus ici : il faut une session pour
/// l'engager, puisque `commit_goal` est reservee au role authenticated. Une
/// fois connecte, l'utilisateur arrive sur l'accueil et son etat vide l'invite
/// a composer son premier defi.
struct OnboardingFlowView: View {
    @State private var isSigningIn = false

    var body: some View {
        WelcomeView(
            onStart: { isSigningIn = true },
            onSignIn: { isSigningIn = true }
        )
        .fullScreenCover(isPresented: $isSigningIn) {
            SignInView()
        }
    }
}

#Preview { OnboardingFlowView() }
