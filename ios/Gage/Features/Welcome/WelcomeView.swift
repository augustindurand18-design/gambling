import SwiftUI

/// Premier ecran de l'application : marque, promesse, entree dans
/// l'onboarding, et raccourci pour un compte existant.
///
/// La vue ne connait aucune destination : elle remonte deux intentions a son
/// appelant, qui decide de la navigation.
struct WelcomeView: View {
    /// « Commencer » : entree dans l'onboarding (creation de compte).
    let onStart: () -> Void
    /// « Se connecter » : retour d'un utilisateur deja inscrit.
    let onSignIn: () -> Void

    /// Baseline de la maquette, en attente de la formulation definitive.
    private let headline = "Lorem ipsum dolor sit amet"

    var body: some View {
        ScreenBackground {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                AppMark()

                Text(headline)
                    .font(Theme.Fonts.display)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, Theme.Spacing.large)

                PrimaryButton(title: "Commencer", action: onStart)
                    .padding(.top, Theme.Spacing.large)

                signInRow
                    .padding(.top, Theme.Spacing.medium)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            // Le bloc est centre dans l'espace restant : reduire cet espace par
            // le bas le remonte au centre optique de la maquette.
            .padding(.bottom, Theme.Spacing.opticalLift)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var signInRow: some View {
        HStack(spacing: Theme.Spacing.small / 2) {
            Text("Déjà un compte ?")
                .font(Theme.Fonts.footnote)
                .foregroundStyle(Theme.Colors.inkMuted)

            Button("Se connecter", action: onSignIn)
                .font(Theme.Fonts.footnoteEmphasis)
                .foregroundStyle(Theme.Colors.brand)
        }
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}
