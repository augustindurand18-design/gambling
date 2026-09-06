import SwiftUI

/// Carte d'un defi en cours sur l'accueil.
///
/// Un defi qui attend un geste se distingue par un contour, pas seulement par
/// une couleur : c'est le seul element de l'ecran sur lequel l'utilisateur
/// peut perdre de l'argent en ne faisant rien.
struct ChallengeCard: View {
    let challenge: ChallengeSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small + 2) {
                HStack(alignment: .top) {
                    StateBadge(state: challenge.state)

                    Spacer(minLength: Theme.Spacing.small)

                    stake
                }

                Text(challenge.displayTitle)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "camera")
                        .font(.system(size: 12, weight: .medium))
                    Text(challenge.proofTitle)
                        .lineLimit(1)

                    if let hint = challenge.sessionHintText {
                        Text("·")
                        Text(hint).lineLimit(1)
                    }

                    if let deadline = challenge.deadline {
                        Text("·")
                        Text(Self.deadlineText(deadline))
                    }
                }
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.medium - 4)
            .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        challenge.isWaitingOnUser ? Theme.Colors.attention : .clear,
                        lineWidth: 1.5
                    )
            }
            .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Ce que la mise est devenue.
    ///
    /// Un objectif tenu n'affiche aucun montant : rien n'a ete preleve, et
    /// montrer une somme la ou il ne s'est rien passe laisserait croire a une
    /// perte. Une mise perdue s'affiche en rouge, precedee d'un moins — c'est
    /// de l'argent qui est parti, l'ecran doit le dire comme un releve de
    /// compte. Tant que rien n'est joue, le montant reste neutre : c'est ce
    /// qui est en jeu, pas ce qui est perdu.
    @ViewBuilder
    private var stake: some View {
        if challenge.state == .closedKept {
            EmptyView()
        } else if challenge.state.hasLostStake {
            Text("−" + Money.format(cents: challenge.stakeCents))
                .font(Theme.Fonts.footnoteEmphasis)
                .foregroundStyle(Theme.Colors.failed)
        } else {
            Text(Money.format(cents: challenge.stakeCents))
                .font(Theme.Fonts.footnoteEmphasis)
                .foregroundStyle(Theme.Colors.ink)
        }
    }

    /// Echeance en clair. Un objectif dont la fenetre est deja ouverte se dit
    /// en temps restant ; les autres se disent a l'heure prevue.
    private static func deadlineText(_ deadline: Date) -> String {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return "échéance dépassée" }
        if remaining < 3600 * 12 {
            // Locale forcee : l'application est monolingue francaise, un
            // telephone en anglais afficherait « dans 11 hrs ».
            let delay = Duration.seconds(remaining).formatted(
                .units(allowed: [.hours, .minutes], maximumUnitCount: 1).locale(Money.locale)
            )
            return "dans \(delay)"
        }
        return deadline.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(Money.locale))
    }
}

/// Pastille d'etat : couleur et libelle, jamais la couleur seule.
struct StateBadge: View {
    let state: GoalState

    var body: some View {
        Text(state.localizedLabel)
            .font(Theme.Fonts.badge)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: .capsule)
    }

    private var tint: Color {
        switch state {
        case .closedKept, .validated:
            Theme.Colors.kept
        case .closedFailed, .chargeOk, .chargeFailed, .chargePending, .rejected:
            Theme.Colors.failed
        case .proofWindowOpen:
            Theme.Colors.attention
        default:
            Theme.Colors.brand
        }
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        VStack(spacing: Theme.Spacing.small + 4) {
            ChallengeCard(
                challenge: ChallengeSummary(
                    id: UUID(),
                    title: "Je me promets de me lever à 7 h 00.",
                    proofTitle: "Photo du lit fait",
                    state: .proofWindowOpen,
                    stakeCents: 2_500,
                    deadline: .now.addingTimeInterval(3_000)
                )
            ) {}

            ChallengeCard(
                challenge: ChallengeSummary(
                    id: UUID(),
                    title: "Je me promets d'aller à la salle à 18 h 30.",
                    proofTitle: "Photo sur place",
                    state: .committed,
                    stakeCents: 1_500,
                    deadline: .now.addingTimeInterval(86_400)
                )
            ) {}
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
