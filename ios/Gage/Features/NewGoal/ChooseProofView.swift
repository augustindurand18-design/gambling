import SwiftUI

/// Choix de la preuve : toutes celles proposees conviennent a l'objectif, la
/// question posee est seulement celle que l'utilisateur accepte de montrer.
///
/// Aucun reglage technique n'est expose, et la phrase composee a l'etape
/// precedente est rappelee sans pouvoir etre modifiee ici : revenir en
/// arriere est le seul moyen de la changer, et ce retour efface la preuve.
struct ChooseProofView: View {
    @Binding var composition: GoalComposition
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total,
                    index: NewGoalStep.proof.index,
                    onBack: { dismiss() }
                )

                Text(composition.sentence)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.medium + 4)

                Divider()
                    .overlay(Theme.Colors.divider)
                    .padding(.top, Theme.Spacing.medium)

                Text("Que photographies-tu ?")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .padding(.top, Theme.Spacing.medium + 4)

                Text("Toutes ces preuves conviennent à cet objectif. Choisis celle que tu es prêt à montrer.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small)

                VStack(spacing: 10) {
                    ForEach(composition.proofs) { proof in
                        SelectableCard(
                            symbol: proof.symbol,
                            title: proof.title,
                            subtitle: proof.subtitle,
                            isSelected: composition.proofID == proof.id
                        ) {
                            composition.proofID = proof.id
                        }
                    }
                }
                .padding(.top, Theme.Spacing.medium + 4)

                Spacer(minLength: Theme.Spacing.medium)

                PrimaryButton(
                    title: "Continuer",
                    isEnabled: composition.selectedProof != nil,
                    action: onContinue
                )
                .accessibilityIdentifier("proof-continue")
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    @Previewable @State var composition = GoalComposition(verbIndex: 1)
    ChooseProofView(composition: $composition, onContinue: {})
}
