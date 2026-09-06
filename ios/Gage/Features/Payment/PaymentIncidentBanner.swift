import SwiftUI

/// Avertissement quand un débit n'a pas abouti.
///
/// Sans lui, l'utilisateur découvre le blocage au pire moment : en essayant de
/// créer un objectif, par un refus qu'il ne comprend pas. Le bandeau dit ce
/// qui s'est passé et ouvre directement la réparation.
///
/// Le texte distingue les deux causes, parce que le geste attendu n'est pas le
/// même : une carte refusée demande d'en changer, une authentification demande
/// de confirmer auprès de sa banque. Les confondre enverrait la moitié des
/// gens changer une carte qui fonctionne.
struct PaymentIncidentBanner: View {
    let outstandingCents: Int
    /// Motif brut venu de `profiles.stake_block_reason`.
    let reason: String?
    var onFix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.failed)

                Text(title)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)
            }

            Text(detail)
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onFix) {
                Text(action)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.onBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.small + 2)
                    .background(Theme.Colors.failed, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityIdentifier("payment-incident-fix")
        }
        .padding(Theme.Spacing.medium - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.Colors.failed.opacity(0.35), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    /// La banque a-t-elle demandé une authentification, plutôt que refusé ?
    private var needsAuthentication: Bool {
        reason?.contains("authentification") == true
    }

    private var title: String {
        needsAuthentication ? "Ta banque demande une confirmation" : "Un débit n'a pas abouti"
    }

    private var detail: String {
        let amount = Money.format(cents: outstandingCents)
        if needsAuthentication {
            return "\(amount) restent à régler. Ta banque a demandé une authentification "
                + "que nous ne pouvons pas faire à ta place. Confirme le paiement pour reprendre."
        }
        return "\(amount) restent à régler. Tant que ce n'est pas fait, tu ne peux pas "
            + "créer de nouvel objectif — mais ceux en cours continuent."
    }

    private var action: String {
        needsAuthentication ? "Confirmer le paiement" : "Mettre ma carte à jour"
    }
}

#Preview("Carte refusée") {
    PaymentIncidentBanner(outstandingCents: 1200, reason: "card_declined") {}
        .padding()
}

#Preview("Authentification") {
    PaymentIncidentBanner(
        outstandingCents: 900,
        reason: "authentification bancaire requise"
    ) {}
        .padding()
}
