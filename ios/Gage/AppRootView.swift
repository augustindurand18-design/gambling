import SwiftUI

/// Racine de navigation. Aiguille selon l'etat d'authentification et
/// d'onboarding ; pour l'instant seul le parcours d'onboarding est maquette.
struct AppRootView: View {
    var body: some View {
        OnboardingFlowView()
    }
}

#Preview { AppRootView() }
