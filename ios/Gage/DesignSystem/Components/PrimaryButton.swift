import SwiftUI

/// Bouton d'action principal : pilule pleine largeur, degrade de marque,
/// libelle blanc suivi d'une fleche.
///
/// C'est le seul bouton qui engage l'utilisateur dans un parcours ; il reste
/// unique par ecran pour que le tap qui compte ne soit jamais ambigu.
struct PrimaryButton: View {
    let title: String
    /// Masquer la fleche pour les actions qui ne font pas avancer un parcours
    /// (confirmation sur place, par exemple).
    var showsChevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                if showsChevron {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .font(Theme.Fonts.button)
            .foregroundStyle(Theme.Colors.onBrand)
            .frame(maxWidth: .infinity, minHeight: 61)
            .background(Theme.Gradients.brand, in: .capsule)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

/// Retour tactile discret : le bouton se retracte legerement au toucher.
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    ScreenBackground {
        PrimaryButton(title: "Commencer") {}
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
