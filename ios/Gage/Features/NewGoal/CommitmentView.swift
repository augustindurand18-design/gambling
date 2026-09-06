import SwiftUI

/// Ecran d'engagement : ce que l'utilisateur promet, ce qu'il devra montrer,
/// ce qu'il risque — puis la signature et le geste qui valide.
///
/// Tout tient sur un seul ecran, sans defilement : le montant ne doit jamais
/// pouvoir etre accepte sans avoir ete lu.
///
/// Le geste declenche deux ecritures, dans cet ordre : les objectifs de la
/// semaine sont crees en brouillon, puis chacun est engage par `commit_goal`,
/// qui cree la mise et enregistre le consentement horodate dans la meme
/// transaction. La base reste l'autorite : elle verifie les plafonds, le
/// moyen de paiement et l'absence de blocage, et refuse si quoi que ce soit
/// manque.
///
/// Si un engagement echoue en cours de route, les objectifs deja engages le
/// restent et les autres demeurent en brouillon. C'est volontaire : annuler
/// un engagement demanderait de defaire un consentement, or ceux-ci sont
/// immuables (invariant 3). L'utilisateur voit ce qui a ete pris.
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
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var plan: GoalPlan { draft.plan }
    private var stakeAmountCents: Int { draft.stakeAmountCents }
    private var isSigned: Bool { !strokes.isEmpty }

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total(skippingVariant: plan.skipsVariantStep),
                    index: NewGoalStep.commitment.index(skippingVariant: plan.skipsVariantStep),
                    onBack: { dismiss() }
                )

                Text("LA CONSIGNE")
                    .font(Theme.Fonts.sectionLabel)
                    .tracking(1.8)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .padding(.top, Theme.Spacing.medium + 8)

                Text(plan.sentence)
                    .font(Theme.Fonts.sentence)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small + 4)

                scheduleRow
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
                    title: isSaving ? "Enregistrement…" : "Glisse pour t'engager",
                    disabledTitle: "Signe pour débloquer",
                    isEnabled: isSigned && !isSaving,
                    onConfirm: commit
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Fonts.cardSubtitle)
                        .foregroundStyle(Theme.Colors.failed)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.small)
                }
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

            Text(plan.selectedProof.map { "\($0.title) requise" } ?? "Preuve photo requise")
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

    /// Les jours et leurs heures, relus avant la signature : c'est sur eux
    /// que porte l'engagement, pas seulement sur la phrase.
    private var scheduleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Colors.inkMuted)

            Text(plan.scheduleText)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
                .lineSpacing(3)
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
            Text("La mise, pour la semaine")
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

    /// Enregistre l'objectif sur le compte connecte, puis confirme.
    ///
    /// La confirmation n'apparait qu'apres l'ecriture : afficher « tu t'es
    /// engage » sur un enregistrement qui a echoue ferait croire a quelqu'un
    /// qu'il a un objectif en cours alors qu'il n'en a aucun.
    private func commit() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            #if DEBUG
            // Un test d'interface tourne sur une session factice : aucune
            // requete ne passerait la RLS.
            if SessionStore.isUITesting {
                finish()
                return
            }
            #endif

            do {
                let account = try await ProfileAPI.shared.load()

                // Le refus se lit avant d'ecrire quoi que ce soit. Creer des
                // brouillons pour echouer a les engager laisserait des
                // objectifs orphelins sur l'accueil.
                if let blocker = account.blocker {
                    isSaving = false
                    errorMessage = blocker
                    return
                }

                let goals = try await GoalsAPI.shared.createGoals(plan: plan)
                do {
                    try await engage(goals, charityID: account.defaultCharityID,
                                     cardLast4: account.pmLast4)
                } catch {
                    // L'engagement refusé laisse des brouillons derrière lui :
                    // sans ce ménage, chaque tentative en dépose une série de
                    // plus sur l'accueil. Ceux déjà engagés sont protégés par
                    // la RLS, qui ne laisse supprimer que les `draft`.
                    await GoalsAPI.shared.deleteDrafts(ids: goals.map(\.id))
                    throw error
                }
                finish()
            } catch {
                isSaving = false
                errorMessage = (error as? AppError)?.errorDescription
                    ?? "Impossible d'enregistrer ton objectif."
            }
        }
    }

    /// Engage chaque seance : une mise et un consentement par objectif.
    ///
    /// Le consentement est hache sur le texte exact affiche, seance par
    /// seance — le libelle du jour en fait partie. Hacher un texte generique
    /// reviendrait a ne pouvoir prouver que le generique.
    private func engage(
        _ goals: [CreatedGoal],
        charityID: UUID?,
        cardLast4: String?
    ) async throws {
        for goal in goals {
            let sealed = ConsentTerms.sealed(
                ConsentTerms.Context(
                    goalTitle: plan.weeklyTitle,
                    proofInstruction: plan.selectedProof.map { "\($0.title) — \($0.subtitle)" },
                    amountCents: stakeAmountCents,
                    charityBps: BusinessRules.charityBps,
                    scheduleText: plan.scheduleText,
                    cardLast4: cardLast4
                )
            )

            try await PaymentAPI.shared.commit(
                goalID: goal.id,
                amountCents: stakeAmountCents,
                charityID: charityID,
                consent: ConsentRecord(
                    goalTitle: plan.weeklyTitle,
                    proofInstruction: plan.selectedProof.map { "\($0.title) — \($0.subtitle)" },
                    amountCents: stakeAmountCents,
                    charityBps: BusinessRules.charityBps,
                    targetDate: goal.targetDate,
                    scheduleText: plan.scheduleText,
                    acceptedAt: .now,
                    termsHash: sealed.hash
                )
            )
        }
    }

    private func finish() {
        isSaving = false
        withAnimation(.easeOut(duration: 0.25)) { signedAt = .now }
        Log.app.debug("Objectif enregistré : \(plan.shortTitle, privacy: .public)")
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
        plan: GoalPlan(
            categoryID: "sport",
            variantID: "gym",
            days: [.monday, .wednesday, .saturday],
            times: [.monday: .fixed(hour: 18, minute: 30), .wednesday: .onTheDay,
                    .saturday: .fixed(hour: 10, minute: 0)],
            proofID: "onsite"
        )
    )
    CommitmentView(draft: $draft, onCommitted: {})
}
