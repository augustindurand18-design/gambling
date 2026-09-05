import SwiftUI

/// Fond degrade commun a tous les ecrans, etendu sous les zones sures.
struct ScreenBackground<Content: View>: View {

    /// Tache lumineuse decorative posee sur le degrade.
    enum Glow {
        case none
        /// Halo cyan debordant en haut a droite (ecrans d'onboarding).
        case topTrailing
    }

    var glow: Glow = .none
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Theme.Gradients.background
                .ignoresSafeArea()

            if case .topTrailing = glow {
                Circle()
                    .fill(Theme.Colors.glow.opacity(0.5))
                    .frame(width: 240, height: 240)
                    .blur(radius: 45)
                    .offset(x: 180, y: 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            content
        }
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) { Text("Contenu") }
}
