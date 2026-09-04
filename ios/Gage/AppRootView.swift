import SwiftUI

/// Racine de navigation : onboarding au premier lancement, accueil ensuite.
///
/// L'aiguillage se fait pour l'instant en memoire, et l'accueil affiche un
/// jeu de demonstration : ni la session ni les objectifs ne sont encore lus
/// depuis Supabase.
struct AppRootView: View {
    @State private var hasOnboarded = false

    var body: some View {
        if hasOnboarded {
            HomeView(snapshot: .sample)
        } else {
            OnboardingFlowView { hasOnboarded = true }
        }
    }
}

#Preview { AppRootView() }
