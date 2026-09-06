import SwiftUI

/// Racine de navigation : accueil de bienvenue tant que personne n'est
/// connecte, application ensuite.
///
/// C'est la session Supabase qui decide, et elle seule. L'ancien drapeau en
/// memoire laissait entrer sans compte, ce qui ne pouvait pas survivre au
/// branchement de la base : sans session, aucune requete ne passe la RLS.
///
/// L'accueil charge lui-meme ses objectifs depuis le serveur.
struct AppRootView: View {
    @State private var session = SessionStore()

    /// Composition du premier defi, avant tout compte.
    ///
    /// Le parcours est presente **ici** et non depuis l'ecran de bienvenue :
    /// la connexion survient au milieu, et la bascule `signedOut` →
    /// `signedIn` remplace le contenu du `Group`. Un plein ecran pose sur
    /// l'ecran de bienvenue disparaitrait avec lui, emportant l'objectif que
    /// l'utilisateur vient de signer. Pose sur le `Group`, il traverse la
    /// bascule sans broncher.
    @State private var isComposingFirstGoal = false

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                // La session est restauree depuis le trousseau : cet ecran
                // dure le temps d'une lecture locale, pas d'un aller-retour
                // reseau.
                ScreenBackground {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.Colors.brand)
                }

            case .signedOut:
                OnboardingFlowView(onCompose: { isComposingFirstGoal = true })

            case .signedIn:
                HomeView()
            }
        }
        .fullScreenCover(isPresented: $isComposingFirstGoal) {
            NewGoalFlowView { isComposingFirstGoal = false }
        }
        .task { await session.observe() }
        .task(id: wantsPushAuthorization) {
            // Sans jeton APNs enregistre, `app.open_due_proof_windows()`
            // refuse d'ouvrir la fenetre : elle ne lance pas un compte a
            // rebours qu'elle ne peut annoncer a personne. L'autorisation
            // n'est donc pas un confort, c'est ce qui rend l'objectif jouable.
            //
            // Redemande a chaque ouverture de session ET a chaque lancement :
            // le jeton change apres une restauration de sauvegarde ou une mise
            // a jour du systeme, et le serveur doit recevoir le nouveau.
            //
            // Jamais pendant la composition du premier defi : l'alerte du
            // systeme tomberait par-dessus le formulaire de carte, au moment
            // precis ou l'on demande a quelqu'un sa confiance.
            guard wantsPushAuthorization else { return }
            await PushAuthorization.requestIfNeeded()
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = session.state { return true }
        return false
    }

    private var wantsPushAuthorization: Bool {
        isSignedIn && !isComposingFirstGoal
    }
}

#Preview { AppRootView() }
