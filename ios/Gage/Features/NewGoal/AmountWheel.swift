import SwiftUI

/// Roue de selection d'un montant.
///
/// Reprend la roue generique avec les mesures de la maquette de mise : lignes
/// hautes, chiffres en gros, valeur retenue au violet de marque.
struct AmountWheel: View {
    /// Montants proposes, en centimes, dans l'ordre d'affichage.
    let amountsCents: [Int]
    @Binding var selectionCents: Int

    var body: some View {
        Wheel(
            values: amountsCents,
            selection: $selectionCents,
            label: { Money.format(cents: $0) },
            rowHeight: Theme.Metrics.amountRow,
            selectedFont: Theme.Fonts.amount,
            mutedFont: Theme.Fonts.amountMuted,
            selectedColor: Theme.Colors.brand,
            bandInset: 7,
            bandCornerRadius: 22
        )
    }
}

#Preview {
    @Previewable @State var amount = BusinessRules.defaultStakeCents
    ScreenBackground(glow: .topTrailing) {
        AmountWheel(
            amountsCents: BusinessRules.suggestedStakes(upTo: BusinessRules.defaultPerGoalCapCents),
            selectionCents: $amount
        )
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
