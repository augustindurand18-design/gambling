import SwiftUI

/// Choix du montant mis en jeu, une fois l'objectif et sa preuve definis.
///
/// La mise couvre la semaine entiere : une seule somme, quel que soit le
/// nombre de seances promises. Une mise par seance multiplierait l'exposition
/// sans que l'utilisateur l'ait lue quelque part.
///
/// Cet ecran ne prend aucun engagement — il ne fait que preparer un montant.
/// Le consentement au debit est donne a l'ecran suivant, avec ses conditions
/// affichees et une signature.
struct StakeAmountView: View {
    @Binding var amountCents: Int
    /// Le plan n'a pas d'usage ici, sinon les points de progression : le
    /// parcours compte une etape de moins quand l'ecran de declinaison a ete
    /// saute. Il arrive par lien et non par copie, comme le brouillon de
    /// l'ecran d'engagement, pour ne pas rester fige sur l'etat d'avant le
    /// choix de la famille.
    @Binding var plan: GoalPlan
    /// Plafond par objectif accepte par l'utilisateur ; borne la roue.
    var capCents: Int = BusinessRules.defaultPerGoalCapCents
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total(skippingVariant: plan.skipsVariantStep),
                    index: NewGoalStep.stake.index(skippingVariant: plan.skipsVariantStep),
                    onBack: { dismiss() }
                )

                Text("Combien tu veux miser ?")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .padding(.top, Theme.Spacing.large)

                Text("Si tu ne tiens pas ta semaine, ce montant sera retiré de ton compte.")
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
    @Previewable @State var plan = GoalPlan(categoryID: "sport", variantID: "gym")
    StakeAmountView(amountCents: $amount, plan: $plan, onContinue: {})
}
