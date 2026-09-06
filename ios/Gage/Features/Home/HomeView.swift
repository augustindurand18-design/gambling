import SwiftUI

/// Accueil de l'application : ce qui est en jeu maintenant, puis la
/// regularite sur la duree.
///
/// L'ordre n'est pas negociable — les defis en cours passent avant
/// l'historique, parce qu'eux seuls peuvent encore couter de l'argent si
/// l'utilisateur ne fait rien.
struct HomeView: View {
    @State private var store: HomeStore
    @State private var isCreating = false
    @State private var isShowingProfile = false
    /// Defi dont la fiche est ouverte.
    @State private var openedChallenge: ChallengeSummary?
    /// Boite aux lettres entre la notification et l'ecran de capture.
    private let router = ProofRouter.shared
    /// Capture demandee depuis la fiche, en attente que celle-ci soit fermee.
    @State private var captureAfterDismiss: PendingProof?
    /// Etat du compte : sert a prevenir d'un debit en souffrance.
    @State private var account: AccountState?
    @State private var isFixingPayment = false
    @State private var isShowingHistory = false

    init(store: HomeStore = HomeStore()) {
        _store = State(wrappedValue: store)
    }

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            switch store.state {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.brand)

            case .failed(let message):
                failure(message)

            case .loaded(let snapshot):
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                        header(snapshot)

                        // Avant tout le reste : un debit en souffrance gele la
                        // creation d'objectifs, et le decouvrir en se faisant
                        // refuser un engagement serait la pire facon de
                        // l'apprendre.
                        if let account, account.stakeBlockActive {
                            PaymentIncidentBanner(
                                outstandingCents: account.outstandingBalanceCents,
                                reason: account.stakeBlockReason
                            ) {
                                isFixingPayment = true
                            }
                        }

                        AssiduityBanner(status: snapshot.assiduity)
                        challenges(snapshot)
                        consistency(snapshot)
                    }
                    .padding(.horizontal, Theme.Spacing.screenHorizontal)
                    .padding(.top, Theme.Spacing.small)
                    .padding(.bottom, Theme.Spacing.large)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await store.loadIfNeeded() }
        .task { await loadAccount() }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .padding(.horizontal, Theme.Spacing.screenHorizontal)
                .padding(.top, Theme.Spacing.medium)
                .padding(.bottom, Theme.Spacing.small)
                .background(Theme.Gradients.bottomFade)
        }
        .fullScreenCover(isPresented: $isCreating) {
            NewGoalFlowView {
                isCreating = false
                // L'objectif vient d'etre engage cote serveur : l'accueil
                // doit le montrer, pas afficher l'etat d'avant.
                Task { await store.reload() }
            }
        }
        .sheet(isPresented: $isFixingPayment) {
            CardEnrollmentView(
                onEnrolled: { Task { await loadAccount() } },
                onSkip: nil
            )
        }
        .sheet(isPresented: $isShowingProfile) {
            ProfileView(assiduity: assiduity)
        }
        .sheet(isPresented: $isShowingHistory) {
            HistoryView(past: pastChallenges)
        }
        // La capture ne peut pas s'ouvrir depuis la fiche : une feuille
        // modale ne peut pas en presenter une seconde. La fiche depose donc
        // sa demande, se ferme, et l'ecran est presente ici une fois la
        // fermeture terminee — sinon SwiftUI ignore la presentation.
        .sheet(item: $openedChallenge, onDismiss: {
            guard let proof = captureAfterDismiss else { return }
            captureAfterDismiss = nil
            router.present(proof)
        }) { challenge in
            ChallengeDetailView(challenge: challenge) { proof in
                captureAfterDismiss = proof
            }
        }
        // Une demande de preuve passe devant tout le reste : la fenetre dure
        // quinze minutes, et l'utilisateur vient de toucher la notification
        // pour ca. `fullScreenCover` et non `sheet` — un ecran qu'on peut
        // faire glisser par megarde n'est pas un ecran ou de l'argent est en jeu.
        .fullScreenCover(item: Binding(
            get: { router.pendingGoal },
            set: { if $0 == nil { router.clear() } }
        )) { pending in
            ProofCaptureView(pending: pending) {
                router.clear()
                // Le defi a change d'etat cote serveur : l'accueil doit le
                // montrer, pas afficher l'etat d'avant.
                Task { await store.reload() }
            }
        }
    }

    // MARK: - Barre du bas

    /// Le « + » au centre, l'historique en satellite a sa droite.
    ///
    /// Les trois emplacements sont de largeur egale : c'est ce qui tient le
    /// « + » au centre exact de l'ecran, et non au centre de ce qui reste
    /// une fois l'historique pose. Celui de gauche attend une troisieme
    /// action et reste vide.
    ///
    /// Le « + » garde le libelle « Nouvel objectif » pour qui n'a que la voix
    /// ou le clavier : un bouton dont le nom est un signe de ponctuation
    /// n'est pas annonçable.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            // `Color` est flexible dans les deux dimensions : sans hauteur
            // bornee sur le HStack, la barre reclamait tout l'ecran et
            // recouvrait la liste des defis, qui devenait intouchable.
            Color.clear
                .frame(maxWidth: .infinity)

            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Theme.Colors.onBrand)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(Theme.Gradients.brand))
            }
            .accessibilityLabel("Nouvel objectif")

            // Le satellite est pousse a gauche de son emplacement pour rester
            // pres du « + » : colle au bord de l'ecran, il se toucherait mal.
            HStack {
                Button {
                    isShowingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.Colors.ink)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Theme.Colors.card))
                        .overlay {
                            Circle().strokeBorder(Theme.Colors.placeholderBorder, lineWidth: 1)
                        }
                }
                .accessibilityLabel("Historique")
                .padding(.leading, Theme.Spacing.small)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 64)
        .buttonStyle(.plain)
    }

    /// Defis termines, ou une liste vide tant que rien n'est charge :
    /// l'historique doit pouvoir s'ouvrir meme pendant un chargement.
    private var pastChallenges: [ChallengeSummary] {
        if case .loaded(let snapshot) = store.state { return snapshot.past }
        return []
    }

    private func loadAccount() async {
        #if DEBUG
        if SessionStore.isUITesting { return }
        #endif
        account = try? await ProfileAPI.shared.load()
    }

    /// L'assiduite du moment, ou un compteur a zero tant que rien n'est
    /// charge : le profil reste ouvrable pendant le chargement.
    private var assiduity: AssiduityStatus {
        if case .loaded(let snapshot) = store.state { return snapshot.assiduity }
        return AssiduityStatus(keptThisWeek: 0)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.medium) {
            Text("Tes défis n'ont pas pu être chargés")
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Réessayer", showsChevron: false) {
                Task { await store.reload() }
            }
            .padding(.top, Theme.Spacing.small)
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }

    private func header(_ snapshot: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer(minLength: 0)
                ProfileButton { isShowingProfile = true }
            }
            .padding(.bottom, Theme.Spacing.small)

            Text("Tes défis")
                .font(Theme.Fonts.display)
                .foregroundStyle(Theme.Colors.ink)

            Text(headerDetail(snapshot))
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
        }
        .padding(.top, Theme.Spacing.small)
    }

    private func headerDetail(_ snapshot: HomeSnapshot) -> String {
        let atRisk = snapshot.challenges.filter { $0.state.hasMoneyAtRisk }
        guard !atRisk.isEmpty else { return "Rien en jeu pour le moment." }
        let total = atRisk.reduce(0) { $0 + $1.stakeCents }
        return "\(Money.format(cents: total)) en jeu sur \(atRisk.count) objectif\(atRisk.count > 1 ? "s" : "")."
    }

    @ViewBuilder
    private func challenges(_ snapshot: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small + 4) {
            Text("En cours")
                .font(Theme.Fonts.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)

            if snapshot.isEmpty {
                emptyChallenges
            } else {
                ForEach(snapshot.challenges) { challenge in
                    ChallengeCard(challenge: challenge) {
                        openedChallenge = challenge
                    }
                }
            }
        }
    }

    private var emptyChallenges: some View {
        VStack(spacing: Theme.Spacing.small) {
            Text("Aucun objectif en cours.")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.ink)

            Text("Compose ton premier défi et mise dessus.")
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.large)
        .background {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(
                    Theme.Colors.placeholderBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
        }
    }

    private func consistency(_ snapshot: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium - 4) {
            Text("Ta régularité")
                .font(Theme.Fonts.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)

            HStack(spacing: Theme.Spacing.small + 4) {
                stat(value: "\(snapshot.calendar.currentStreak)", label: "jours de suite")
                stat(value: "\(snapshot.calendar.keptCount)", label: "objectifs tenus")
                stat(value: "\(snapshot.calendar.failedCount)", label: "manqués")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.medium - 4) {
                ConsistencyGrid(calendar: snapshot.calendar)
                ConsistencyLegend()
            }
            .padding(Theme.Spacing.medium - 4)
            .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        }
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Fonts.stat)
                .foregroundStyle(Theme.Colors.ink)
            Text(label)
                .font(Theme.Fonts.calendarLegend)
                .foregroundStyle(Theme.Colors.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.small + 2)
        .padding(.horizontal, Theme.Spacing.small + 4)
        .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Avec défis") { HomeView(store: HomeStore(state: .loaded(.sample))) }

#Preview("Compte neuf") { HomeView(store: HomeStore(state: .loaded(.empty))) }

#Preview("Chargement") { HomeView(store: HomeStore(state: .loading)) }

#Preview("Échec") { HomeView(store: HomeStore(state: .failed("Connexion impossible. Vérifie ton réseau et réessaie."))) }
