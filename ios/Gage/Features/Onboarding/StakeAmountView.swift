import SwiftUI

/// Etape 1 de l'onboarding : choix du montant mis en jeu.
///
/// Cet ecran ne prend aucun engagement — il ne fait que preparer un montant.
/// Le consentement au debit est donne plus tard, ecran dedie, sur un objectif
/// precis et avec ses conditions affichees.
struct StakeAmountView: View {
    @Binding var amountCents: Int
    /// Plafond par objectif accepte par l'utilisateur ; borne la roue.
    var capCents: Int = BusinessRules.defaultPerGoalCapCents
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: OnboardingStep.total,
                    index: OnboardingStep.stakeAmount.index,
                    onBack: { dismiss() }
                )

                Text("Combien tu veux miser ?")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .padding(.top, Theme.Spacing.large)

                Text("Si tu ne réussis pas ton objectif, ce montant sera retiré de ton compte.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small + 4)

                Spacer(minLength: Theme.Spacing.large)

                AmountWheel(
                    amountsCents: BusinessRules.suggestedStakes(upTo: capCents),
                    selectionCents: $amountCents
                )

                Spacer(minLength: Theme.Spacing.large)

                PrimaryButton(
                    title: "Continuer avec \(Money.format(cents: amountCents))",
                    showsChevron: false,
                    action: onContinue
                )

                Text("Modifiable à tout moment")
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.small + 4)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    @Previewable @State var amount = BusinessRules.defaultStakeCents
    StakeAmountView(amountCents: $amount, onContinue: {})
}
