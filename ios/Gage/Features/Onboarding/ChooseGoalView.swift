import SwiftUI

/// Etape 2 de l'onboarding : choix du premier objectif.
///
/// Les emplacements pointilles sous la liste marquent la place des modeles a
/// venir. Ils ne sont pas interactifs et ne promettent rien de precis.
struct ChooseGoalView: View {
    let templates: [GoalTemplate]
    let onSelect: (GoalTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: OnboardingStep.total,
                    index: OnboardingStep.goal.index,
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
                    ForEach(templates) { template in
                        ChoiceCard(title: template.title) { onSelect(template) }
                    }

                    ForEach(0..<GoalTemplate.onboardingPlaceholderCount, id: \.self) { _ in
                        ChoiceCardPlaceholder()
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
    ChooseGoalView(templates: GoalTemplate.onboarding) { _ in }
}
