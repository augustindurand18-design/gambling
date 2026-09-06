import SwiftUI

/// Historique : les defis termines, tenus comme perdus.
///
/// Ecran de lecture seule. Rien n'y appelle un geste — c'est justement ce qui
/// le separe de l'accueil, ou tout ce qui est affiche peut encore couter de
/// l'argent si personne ne bouge.
///
/// Les echecs y figurent au meme titre que les reussites. Les masquer
/// flatterait l'utilisateur en lui mentant sur sa propre regularite, alors
/// que c'est precisement ce qu'il vient verifier.
struct HistoryView: View {
    let past: [ChallengeSummary]

    @Environment(\.dismiss) private var dismiss
    @State private var opened: ChallengeSummary?

    var body: some View {
        NavigationStack {
            ScreenBackground(glow: .topTrailing) {
                if past.isEmpty {
                    empty
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.medium) {
                            ForEach(past) { challenge in
                                ChallengeCard(challenge: challenge) {
                                    opened = challenge
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenHorizontal)
                        .padding(.top, Theme.Spacing.small)
                        .padding(.bottom, Theme.Spacing.large)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.Colors.brand)
                }
            }
            .sheet(item: $opened) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.inkMuted)

            Text("Rien encore")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.ink)

            Text("Tes défis terminés apparaîtront ici, tenus comme manqués.")
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HistoryView(past: [])
}
