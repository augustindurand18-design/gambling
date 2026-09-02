import SwiftUI

/// Racine de navigation. Aiguille selon l'etat d'authentification et
/// d'onboarding. Le design reel viendra remplacer ces vues.
struct AppRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Gage")
                .font(.largeTitle.bold())
            Text("Squelette — le design arrive")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview { AppRootView() }
