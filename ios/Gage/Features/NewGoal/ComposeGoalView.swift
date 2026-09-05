import SwiftUI

/// Composition de l'objectif : trois roues en cascade, et la phrase qu'elles
/// forment au-dessus.
///
/// L'objectif n'est pas saisi au clavier mais compose : le catalogue ne
/// propose que des promesses dont la preuve photo est verifiable. Un champ
/// libre laisserait l'utilisateur s'engager sur « etre plus gentil », qui
/// n'est ni verifiable ni refusable proprement le jour du controle.
struct ComposeGoalView: View {
    @Binding var composition: GoalComposition
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total,
                    index: NewGoalStep.goal.index,
                    onBack: { dismiss() }
                )

                Text(composition.sentence)
                    .font(Theme.Fonts.sentence)
                    .foregroundStyle(composition.isGoalChosen ? Theme.Colors.ink : Theme.Colors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
                    .animation(.easeOut(duration: 0.2), value: composition.sentence)
                    .padding(.top, Theme.Spacing.large)

                Spacer(minLength: Theme.Spacing.medium)

                VStack(spacing: Theme.Spacing.small) {
                    verbWheel
                    complementWheel
                    timeWheels
                }

                Spacer(minLength: Theme.Spacing.medium)

                PrimaryButton(
                    title: "Continuer",
                    isEnabled: composition.isGoalChosen,
                    action: onContinue
                )
                // L'ecran precedent reste dans la pile avec un bouton du meme
                // libelle : sans identifiant, une requete d'interface ne sait
                // pas lequel des deux elle designe.
                .accessibilityIdentifier("compose-continue")

                Text("Seuls des objectifs prouvables en photo.")
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.small + 4)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var verbWheel: some View {
        Wheel(
            values: Array(GoalCatalogue.verbs.indices),
            selection: Binding(
                get: { composition.verbIndex },
                set: { composition.selectVerb($0) }
            ),
            label: { GoalCatalogue.verbs[$0].label }
        )
        .accessibilityLabel("Verbe de l'objectif")
    }

    private var complementWheel: some View {
        Wheel(
            values: Array(composition.complements.indices),
            selection: Binding(
                get: { composition.complementIndex },
                set: { composition.selectComplement($0) }
            ),
            label: { composition.complements[$0].label }
        )
        .accessibilityLabel("Complément de l'objectif")
    }

    /// Heure et minutes partagent un seul cadre de selection, sinon les deux
    /// roues se lisent comme deux reglages separes au lieu d'une heure.
    private var timeWheels: some View {
        ZStack {
            WheelSelectionBand(height: Theme.Metrics.wheelRow - Theme.Metrics.wheelBandInset)

            HStack(spacing: 6) {
                Wheel(
                    values: GoalCatalogue.hours,
                    selection: $composition.hour,
                    label: { String(format: "%02d", $0) },
                    alignment: .trailing,
                    showsBand: false
                )
                .frame(width: 92)
                .accessibilityLabel("Heure")

                Text(":")
                    .font(Theme.Fonts.option)
                    .foregroundStyle(Theme.Colors.ink)

                Wheel(
                    values: GoalCatalogue.minutes,
                    selection: $composition.minute,
                    label: { String(format: "%02d", $0) },
                    alignment: .leading,
                    showsBand: false
                )
                .frame(width: 92)
                .accessibilityLabel("Minutes")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    @Previewable @State var composition = GoalComposition()
    ComposeGoalView(composition: $composition, onContinue: {})
}
