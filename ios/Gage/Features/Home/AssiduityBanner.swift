import SwiftUI

/// Avancement vers la remise d'assiduite.
///
/// Le texte parle toujours de remise obtenue, jamais de penalite encourue :
/// c'est une contrainte juridique autant qu'un choix de ton, la formulation
/// inverse ferait ressembler le tarif a une clause penale.
struct AssiduityBanner: View {
    let status: AssiduityStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small + 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)

                Spacer(minLength: Theme.Spacing.small)

                Text(status.isDiscountEarned ? "5 €/mois" : "25 €/mois")
                    .font(Theme.Fonts.footnoteEmphasis)
                    .foregroundStyle(status.isDiscountEarned ? Theme.Colors.kept : Theme.Colors.inkMuted)
            }

            ProgressView(value: status.progress)
                .tint(status.isDiscountEarned ? Theme.Colors.kept : Theme.Colors.brand)

            Text(detail)
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.medium - 4)
        .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        status.isDiscountEarned ? "Remise d'assiduité obtenue" : "Remise d'assiduité"
    }

    private var detail: String {
        if status.isDiscountEarned {
            return "\(status.keptThisWeek) objectifs tenus cette semaine. Tu gardes le tarif réduit."
        }
        let remaining = status.remaining
        let plural = remaining > 1 ? "objectifs tenus" : "objectif tenu"
        return "Encore \(remaining) \(plural) cette semaine pour passer à 5 €/mois."
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        VStack(spacing: Theme.Spacing.medium) {
            AssiduityBanner(status: AssiduityStatus(keptThisWeek: 1))
            AssiduityBanner(status: AssiduityStatus(keptThisWeek: 3))
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
