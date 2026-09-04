import SwiftUI

/// Carte d'un choix unique dans une liste : symbole, titre, explication, et
/// une pastille a droite qui montre laquelle est retenue.
///
/// La pastille est doublee d'un contour de marque : la selection ne repose
/// pas sur la seule couleur du rond, invisible pour qui ne la distingue pas.
struct SelectableCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.Colors.brand : Theme.Colors.inkMuted)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(Theme.Fonts.cardSubtitle)
                        .foregroundStyle(Theme.Colors.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                radio
            }
            .multilineTextAlignment(.leading)
            .padding(Theme.Spacing.medium - 4)
            .background(
                isSelected ? Theme.Colors.cardSelected : Theme.Colors.card,
                in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Colors.brand : Color.clear,
                        lineWidth: 1.5
                    )
            }
            .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var radio: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Theme.Colors.brand : Theme.Colors.placeholderBorder,
                    lineWidth: 1.5
                )
                .frame(width: 20, height: 20)

            if isSelected {
                Circle()
                    .fill(Theme.Colors.brand)
                    .frame(width: 11, height: 11)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        VStack(spacing: 10) {
            SelectableCard(
                symbol: "mappin.and.ellipse",
                title: "Photo de l'extérieur",
                subtitle: "Prouve que tu es sorti de chez toi",
                isSelected: true
            ) {}
            SelectableCard(
                symbol: "bed.double",
                title: "Photo du lit fait",
                subtitle: "Prouve que tu as quitté le lit",
                isSelected: false
            ) {}
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
