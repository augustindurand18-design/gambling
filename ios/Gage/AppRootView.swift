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
                OnboardingFlowView()

            case .signedIn:
                HomeView()
            }
        }
        .task { await session.observe() }
    }
}

#Preview { AppRootView() }
