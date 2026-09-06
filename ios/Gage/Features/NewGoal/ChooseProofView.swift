import SwiftUI

/// Choix de la preuve : toutes celles proposees conviennent a l'objectif, la
/// question posee est seulement celle que l'utilisateur accepte de montrer.
///
/// Aucun reglage technique n'est expose, et la promesse definie aux etapes
/// precedentes est rappelee sans pouvoir etre modifiee ici : revenir en
/// arriere est le seul moyen de la changer, et ce retour efface la preuve.
///
/// Certains objectifs n'ont qu'une preuve possible — un lieu se prouve par la
/// photo sur place, et rien d'autre. L'ecran reste affiche quand meme : il ne
/// fait plus choisir, il annonce ce qu'il faudra photographier, et c'est cette
/// annonce prealable qui permet de tenir la promesse le jour du controle.
struct ChooseProofView: View {
    @Binding var plan: GoalPlan
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var hasChoice: Bool { plan.proofs.count > 1 }

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total(skippingVariant: plan.skipsVariantStep),
                    index: NewGoalStep.proof.index(skippingVariant: plan.skipsVariantStep),
                    onBack: { dismiss() }
                )

                Text(plan.sentence)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.medium + 4)

                Divider()
                    .overlay(Theme.Colors.divider)
                    .padding(.top, Theme.Spacing.medium)

                Text(hasChoice ? "Que photographies-tu ?" : "Voici ce que tu photographieras")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.medium + 4)

                Text(hasChoice
                     ? "Toutes ces preuves conviennent à cet objectif. Choisis celle que tu es prêt à montrer."
                     : "C'est la seule preuve qui vaut pour cet objectif. Tu la connais dès maintenant : le jour du contrôle, seule l'heure sera une surprise.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small)

                VStack(spacing: 10) {
                    ForEach(plan.proofs) { proof in
                        SelectableCard(
                            symbol: proof.symbol,
                            title: proof.title,
                            subtitle: proof.subtitle,
                            isSelected: plan.proofID == proof.id
                        ) {
                            plan.proofID = proof.id
                        }
                    }
                }
                .padding(.top, Theme.Spacing.medium + 4)

                Spacer(minLength: Theme.Spacing.medium)

                PrimaryButton(
                    title: "Continuer",
                    isEnabled: plan.selectedProof != nil,
                    action: onContinue
                )
                .accessibilityIdentifier("proof-continue")
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Preuve unique : rien a choisir, on la retient d'office pour ne
            // pas exiger un geste qui n'a pas d'alternative.
            if !hasChoice, let only = plan.proofs.first { plan.proofID = only.id }
        }
    }
}

#Preview("Preuve unique") {
    @Previewable @State var plan = GoalPlan(categoryID: "sport", variantID: "gym")
    ChooseProofView(plan: $plan, onContinue: {})
}

#Preview("Plusieurs preuves") {
    @Previewable @State var plan = GoalPlan(categoryID: "tidy", variantID: "bed")
    ChooseProofView(plan: $plan, onContinue: {})
}
