import SwiftUI

/// Ce qu'il manque pour engager, demande au dernier moment.
///
/// Un nouveau venu compose son premier defi sans compte et sans carte : rien
/// de ce qu'il fait avant la signature ne touche au serveur. Le compte et la
/// carte ne sont reclames qu'ici, une fois qu'il sait exactement ce qu'il
/// promet et ce qu'il risque. Demander l'inverse — la carte avant la
/// promesse — reviendrait a faire payer l'entree d'un magasin.
///
/// L'ordre n'est pas negociable techniquement : `stripe-setup-intent` exige un
/// jeton Supabase, donc la session precede toujours la carte.
struct EngagementGateView: View {

    enum Step: Identifiable, Equatable {
        /// Ni compte ni carte : les deux temps s'enchainent.
        case signIn
        /// Compte deja ouvert, carte manquante.
        case card

        var id: Self { self }
    }

    /// Appele quand le compte porte une carte utilisable. L'appelant reprend
    /// alors l'engagement la ou il l'avait laisse.
    let onReady: () -> Void

    @State private var step: Phase
    @Environment(\.dismiss) private var dismiss

    init(startingAt step: Step, onReady: @escaping () -> Void) {
        self.onReady = onReady
        _step = State(initialValue: step == .signIn ? .signIn : .card)
    }

    private enum Phase: Equatable {
        case signIn
        case card
        /// La carte est partie chez Stripe ; on attend que le compte la porte.
        case confirming
        case failed(String)
    }

    var body: some View {
        switch step {
        case .signIn:
            // Pas de renoncement propose : on est deja au milieu d'un geste
            // engage. Le retour de l'ecran referme la feuille.
            SignInView(onSignedIn: { step = .card })

        case .card:
            CardEnrollmentView(onEnrolled: { step = .confirming })

        case .confirming:
            waiting

        case .failed(let message):
            failure(message)
        }
    }

    // MARK: - Attente du webhook

    private var waiting: some View {
        ScreenBackground {
            VStack(spacing: Theme.Spacing.medium) {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.brand)

                Text("On vérifie ta carte…")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)

                Text("Quelques secondes, le temps que ta banque confirme.")
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
        }
        .task { await waitForCard() }
    }

    private func failure(_ message: String) -> some View {
        ScreenBackground {
            VStack(spacing: Theme.Spacing.medium) {
                Text(message)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Réessayer", showsChevron: false) {
                    step = .confirming
                }

                Button("Fermer") { dismiss() }
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
        }
    }

    /// Attend que le profil porte le moyen de paiement.
    ///
    /// `CardEnrollmentView` sait seulement que Stripe a accepte la carte ; ce
    /// qui autorise un debit, c'est `profiles.default_payment_method_id`, et
    /// c'est le webhook `setup_intent.succeeded` qui l'ecrit. Entre les deux
    /// il y a un aller-retour reseau que rien ne borne. Enchainer sur
    /// `commit_goal` sans attendre le ferait refuser par intermittence, avec
    /// un message parlant d'une carte que l'utilisateur vient pourtant de
    /// saisir — le pire des messages, puisqu'il accuse a tort.
    private func waitForCard() async {
        for attempt in 0..<20 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }

            if let account = try? await ProfileAPI.shared.load(),
               account.defaultPaymentMethodID != nil {
                onReady()
                return
            }
        }

        // Vingt secondes sans retour : on ne dit pas que la carte a echoue, on
        // ne le sait pas. Elle est peut-etre enregistree et le webhook en
        // retard.
        step = .failed(
            "Ta carte n'est pas encore confirmée. Attends un instant et réessaie — "
                + "rien n'a été prélevé."
        )
    }
}

#Preview {
    EngagementGateView(startingAt: .signIn, onReady: {})
}
