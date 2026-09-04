import SwiftUI

/// Roue de selection d'un montant : la valeur choisie est celle qui s'aligne
/// dans le cadre central. Le defilement s'aimante sur les valeurs, et un tap
/// sur un montant voisin l'amene au centre.
struct AmountWheel: View {
    /// Montants proposes, en centimes, dans l'ordre d'affichage.
    let amountsCents: [Int]
    @Binding var selectionCents: Int

    /// Position du defilement. Distincte de la selection : elle passe a nil
    /// pendant le geste, alors que la selection, elle, reste toujours definie.
    @State private var scrolledCents: Int?

    private let rowHeight: CGFloat = 98
    private let bandHeight: CGFloat = 91
    private var viewportHeight: CGFloat { rowHeight * 3 }

    var body: some View {
        ZStack {
            selectionBand

            ScrollView(.vertical) {
                // Pile non paresseuse : une poignee de montants, et le
                // defilement programme vise une ligne qui doit deja exister.
                VStack(spacing: 0) {
                    ForEach(amountsCents, id: \.self) { cents in
                        row(cents)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledCents, anchor: .center)
            // Laisse la premiere et la derniere valeur atteindre le centre.
            .contentMargins(.vertical, rowHeight, for: .scrollContent)
            .frame(height: viewportHeight)
        }
        .task {
            // La position initiale ne peut etre posee qu'apres la premiere
            // passe de mise en page : donnee avant, elle est ignoree et la
            // roue s'ouvre sur la premiere valeur au lieu de la selection.
            await Task.yield()
            scrolledCents = selectionCents
        }
        .onChange(of: scrolledCents) { _, new in
            if let new { selectionCents = new }
        }
        .onChange(of: selectionCents) { _, new in
            guard scrolledCents != new else { return }
            withAnimation(.easeOut(duration: 0.25)) { scrolledCents = new }
        }
        .sensoryFeedback(.selection, trigger: selectionCents)
    }

    private var selectionBand: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Theme.Colors.surface.opacity(0.35))
            .frame(height: bandHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.Colors.selectionBorder, lineWidth: 1.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func row(_ cents: Int) -> some View {
        let isSelected = cents == selectionCents
        return Button {
            selectionCents = cents
        } label: {
            Text(Money.format(cents: cents))
                .font(isSelected ? Theme.Fonts.amount : Theme.Fonts.amountMuted)
                .foregroundStyle(isSelected ? Theme.Colors.brand : Theme.Colors.inkFaded)
                .frame(maxWidth: .infinity)
                .frame(height: rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
