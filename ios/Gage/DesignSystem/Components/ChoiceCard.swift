import SwiftUI

/// Carte de choix : un libelle, un chevron, toute la largeur.
struct ChoiceCard: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)

                Spacer(minLength: Theme.Spacing.small)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.placeholderBorder)
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .frame(height: Theme.Metrics.cardHeight)
            .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Emplacement vide : marque la place d'un choix a venir, sans rien promettre.
struct ChoiceCardPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .strokeBorder(
                Theme.Colors.placeholderBorder,
                style: StrokeStyle(lineWidth: 1, dash: [6, 5])
            )
            .frame(height: Theme.Metrics.cardHeight)
            .accessibilityHidden(true)
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        VStack(spacing: Theme.Spacing.medium) {
            ChoiceCard(title: "Se réveiller à l'heure") {}
            ChoiceCardPlaceholder()
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
