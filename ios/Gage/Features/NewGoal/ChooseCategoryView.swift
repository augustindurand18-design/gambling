import SwiftUI

/// Etape 1 : la famille d'objectif, en liste generique.
///
/// L'objectif ne se saisit pas au clavier : le catalogue ne propose que des
/// promesses dont la preuve photo est verifiable. Un champ libre laisserait
/// quelqu'un s'engager sur « etre plus gentil », qui n'est ni verifiable ni
/// refusable proprement le jour du controle.
struct ChooseCategoryView: View {
    @Binding var plan: GoalPlan
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total,
                    index: NewGoalStep.category.index,
                    onBack: { dismiss() }
                )

                Text("Qu'est-ce que tu veux te forcer à faire ?")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.large)

                Text("Choisis-en un, et assume.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .padding(.top, Theme.Spacing.small + 4)

                VStack(spacing: Theme.Spacing.medium) {
                    ForEach(GoalCatalogue.categories) { category in
                        ChoiceCard(title: category.title) {
                            plan.selectCategory(category.id)
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
    @Previewable @State var plan = GoalPlan()
    ChooseCategoryView(plan: $plan, onSelect: {})
}
