import SwiftUI

/// Etape 2 : la declinaison, propre a la famille choisie.
///
/// Le sous-menu existe parce que la preuve depend de ce qu'on fait vraiment :
/// « la salle » et « la course » ne se montrent pas de la meme facon.
struct ChooseVariantView: View {
    @Binding var plan: GoalPlan
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total,
                    index: NewGoalStep.variant.index,
                    onBack: { dismiss() }
                )

                Text(plan.category?.title ?? "")
                    .font(Theme.Fonts.sectionLabel)
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .padding(.top, Theme.Spacing.medium + 8)

                Text(plan.category?.question ?? "")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small)

                VStack(spacing: Theme.Spacing.medium) {
                    ForEach(plan.variants) { variant in
                        ChoiceCard(title: variant.title) {
                            plan.selectVariant(variant.id)
                            onSelect()
                        }
                    }
                }
                .padding(.top, Theme.Spacing.large)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    @Previewable @State var plan = GoalPlan(categoryID: "sport")
    ChooseVariantView(plan: $plan, onSelect: {})
}
