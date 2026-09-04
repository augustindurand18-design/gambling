import SwiftUI

/// Accueil de l'application : ce qui est en jeu maintenant, puis la
/// regularite sur la duree.
///
/// L'ordre n'est pas negociable — les defis en cours passent avant
/// l'historique, parce qu'eux seuls peuvent encore couter de l'argent si
/// l'utilisateur ne fait rien.
struct HomeView: View {
    let snapshot: HomeSnapshot

    @State private var isCreating = false

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                    header
                    AssiduityBanner(status: snapshot.assiduity)
                    challenges
                    consistency
                }
                .padding(.horizontal, Theme.Spacing.screenHorizontal)
                .padding(.top, Theme.Spacing.small)
                .padding(.bottom, Theme.Spacing.large)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Nouvel objectif", showsChevron: false) {
                isCreating = true
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.medium)
            .padding(.bottom, Theme.Spacing.small)
            .background(Theme.Gradients.bottomFade)
        }
        .fullScreenCover(isPresented: $isCreating) {
            NewGoalFlowView { isCreating = false }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tes défis")
                .font(Theme.Fonts.display)
                .foregroundStyle(Theme.Colors.ink)

            Text(headerDetail)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
        }
        .padding(.top, Theme.Spacing.medium)
    }

    private var headerDetail: String {
        let atRisk = snapshot.challenges.filter { $0.state.hasMoneyAtRisk }
        guard !atRisk.isEmpty else { return "Rien en jeu pour le moment." }
        let total = atRisk.reduce(0) { $0 + $1.stakeCents }
        return "\(Money.format(cents: total)) en jeu sur \(atRisk.count) objectif\(atRisk.count > 1 ? "s" : "")."
    }

    @ViewBuilder
    private var challenges: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small + 4) {
            Text("En cours")
                .font(Theme.Fonts.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)

            if snapshot.isEmpty {
                emptyChallenges
            } else {
                ForEach(snapshot.challenges) { challenge in
                    ChallengeCard(challenge: challenge) {
                        Log.app.debug("Accueil : defi ouvert \(challenge.id, privacy: .public)")
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

    private var consistency: some View {
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

#Preview("Avec défis") { HomeView(snapshot: .sample) }

#Preview("Compte neuf") { HomeView(snapshot: .empty) }
