import SwiftUI

/// Ecran d'engagement : ce que l'utilisateur promet, ce qu'il devra montrer,
/// ce qu'il risque — puis la signature et le geste qui valide.
///
/// Tout tient sur un seul ecran, sans defilement : le montant ne doit jamais
/// pouvoir etre accepte sans avoir ete lu.
///
/// L'ecran ne fait pour l'instant qu'afficher et recueillir le geste. Rien
/// n'est envoye au serveur : l'enregistrement horodate du consentement et
/// l'appel a `commit_goal` viendront avec le branchement Stripe, et c'est la
/// base qui restera l'autorite sur l'engagement.
struct CommitmentView: View {
    /// Le brouillon arrive par lien et non par copie : la fermeture qui
    /// construit cet ecran est enregistree une fois par la pile de navigation,
    /// et une valeur passee par copie y resterait figee sur l'etat d'avant la
    /// composition — l'utilisateur signerait un objectif vide.
    @Binding var draft: GoalDraft
    let onCommitted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [[CGPoint]] = []
    @State private var signedAt: Date?

    private var composition: GoalComposition { draft.composition }
    private var stakeAmountCents: Int { draft.stakeAmountCents }
    private var isSigned: Bool { !strokes.isEmpty }

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total,
                    index: NewGoalStep.commitment.index,
                    onBack: { dismiss() }
                )

                Text("LA CONSIGNE")
                    .font(Theme.Fonts.sectionLabel)
                    .tracking(1.8)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .padding(.top, Theme.Spacing.medium + 8)

                Text(composition.sentence)
                    .font(Theme.Fonts.sentence)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small + 4)

                proofRow
                stakeRow

                Spacer(minLength: Theme.Spacing.medium)

                SignaturePad(strokes: $strokes)

                Text("Ta signature et l'heure exacte de ce geste sont conservées comme preuve de ton consentement.")
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small + 4)

                Spacer(minLength: Theme.Spacing.medium)

                SlideToConfirm(
                    title: "Glisse pour t'engager",
                    disabledTitle: "Signe pour débloquer",
                    isEnabled: isSigned,
                    onConfirm: commit
                )
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)

            if signedAt != nil {
                confirmation
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var proofRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Colors.inkMuted)

            Text(composition.selectedProof.map { "\($0.title) requise" } ?? "Preuve photo requise")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.medium)
        .overlay(alignment: .top) {
            Divider().overlay(Theme.Colors.divider)
        }
        .padding(.top, Theme.Spacing.medium)
    }

    private var stakeRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("La mise")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)

            Spacer(minLength: Theme.Spacing.small)

            Text(Money.format(cents: stakeAmountCents))
                .font(Theme.Fonts.recapAmount)
                .foregroundStyle(Theme.Colors.ink)
        }
        .padding(.top, Theme.Spacing.medium)
        .overlay(alignment: .top) {
            Divider().overlay(Theme.Colors.divider)
        }
        .padding(.top, Theme.Spacing.medium)
    }

    private var confirmation: some View {
        ZStack {
            Theme.Gradients.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.medium) {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.Colors.onBrand)
                    .frame(width: 88, height: 88)
                    .background(Theme.Gradients.brand, in: .circle)

                Text("Tu t'es engagé.")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)

                Text(confirmationDetail)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 260)

                PrimaryButton(title: "Terminer", showsChevron: false, action: onCommitted)
                    .padding(.top, Theme.Spacing.medium)
                    .padding(.horizontal, Theme.Spacing.screenHorizontal)
            }
            .padding(.bottom, Theme.Spacing.opticalLift)
        }
        .transition(.opacity)
    }

    private var confirmationDetail: String {
        let amount = Money.format(cents: stakeAmountCents)
        guard let signedAt else { return "\(amount) engagés." }
        return "\(amount) engagés · signature enregistrée à \(Self.timeFormatter.string(from: signedAt))."
    }

    private func commit() {
        withAnimation(.easeOut(duration: 0.25)) { signedAt = .now }
        Log.app.debug("Engagement signé : \(composition.shortTitle, privacy: .public)")
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Money.locale
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter
    }()
}

#Preview {
    @Previewable @State var draft = GoalDraft(
        composition: GoalComposition(verbIndex: 1, proofID: "bed")
    )
    CommitmentView(draft: $draft, onCommitted: {})
}
