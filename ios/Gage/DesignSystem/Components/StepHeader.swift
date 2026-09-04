import SwiftUI

/// En-tete des ecrans d'un parcours : retour a gauche, progression au centre.
///
/// Les points restent centres sur l'ecran quelle que soit la presence du
/// bouton retour — ils sont poses en dessous, pas a cote.
struct StepHeader: View {
    let count: Int
    let index: Int
    let onBack: () -> Void

    var body: some View {
        PageIndicator(count: count, index: index)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                BackButton(action: onBack)
            }
    }
}

/// Bouton de retour : chevron sur une pastille claire, zone tactile de 44 pt.
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.ink)
                .frame(width: 36, height: 36)
                .background(Theme.Colors.card, in: .circle)
                .shadow(color: Theme.Colors.ink.opacity(0.06), radius: 8, y: 3)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retour")
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        StepHeader(count: 4, index: 1) {}
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
