import SwiftUI

/// Roue de selection : la valeur choisie est celle qui s'aligne dans le cadre
/// central. Le defilement s'aimante sur les valeurs, et un tap sur une valeur
/// voisine l'amene au centre.
///
/// Le composant est generique parce que le parcours enchaine des roues de
/// natures differentes — verbe, complement, heure, minute, montant — qui
/// doivent toutes reagir exactement pareil sous le doigt.
struct Wheel<Value: Hashable>: View {
    /// Valeurs proposees, dans l'ordre d'affichage.
    let values: [Value]
    @Binding var selection: Value
    /// Texte affiche pour une valeur.
    let label: (Value) -> String

    var rowHeight: CGFloat = Theme.Metrics.wheelRow
    var visibleRows: Int = 3
    var selectedFont: Font = Theme.Fonts.option
    var mutedFont: Font = Theme.Fonts.optionMuted
    var selectedColor: Color = Theme.Colors.ink
    var alignment: Alignment = .center
    /// Cadre de selection. Masque quand plusieurs roues partagent un meme
    /// cadre dessine par l'ecran (heure et minutes, par exemple).
    var showsBand: Bool = true
    var bandInset: CGFloat = Theme.Metrics.wheelBandInset
    var bandCornerRadius: CGFloat = 14

    /// Position du defilement. Distincte de la selection : elle passe a nil
    /// pendant le geste, alors que la selection, elle, reste toujours definie.
    @State private var scrolled: Value?

    private var viewportHeight: CGFloat { rowHeight * CGFloat(visibleRows) }
    /// Marge qui laisse la premiere et la derniere valeur atteindre le centre.
    private var edgeMargin: CGFloat { rowHeight * CGFloat(visibleRows - 1) / 2 }

    var body: some View {
        ZStack {
            if showsBand {
                WheelSelectionBand(height: rowHeight - bandInset, cornerRadius: bandCornerRadius)
            }

            ScrollView(.vertical) {
                // Pile non paresseuse : une poignee de valeurs, et le
                // defilement programme vise une ligne qui doit deja exister.
                VStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        row(value)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolled, anchor: .center)
            .contentMargins(.vertical, edgeMargin, for: .scrollContent)
            .frame(height: viewportHeight)
        }
        .task {
            // La position initiale ne peut etre posee qu'apres la premiere
            // passe de mise en page : donnee avant, elle est ignoree et la
            // roue s'ouvre sur la premiere valeur au lieu de la selection.
            await Task.yield()
            scrolled = selection
        }
        .onChange(of: scrolled) { _, new in
            if let new { selection = new }
        }
        .onChange(of: selection) { _, new in
            guard scrolled != new else { return }
            withAnimation(.easeOut(duration: 0.25)) { scrolled = new }
        }
        .onChange(of: values) { _, _ in
            // La liste vient d'etre remplacee par la cascade amont : la
            // position retenue designe une ligne qui n'existe plus, et sans
            // ce recalage la roue reste bloquee sur du vide.
            scrolled = selection
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(_ value: Value) -> some View {
        let isSelected = value == selection
        return Button {
            selection = value
        } label: {
            Text(label(value))
                .font(isSelected ? selectedFont : mutedFont)
                .foregroundStyle(isSelected ? selectedColor : Theme.Colors.inkFaded)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
                .frame(height: rowHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Cadre clair qui materialise la ligne selectionnee d'une roue.
struct WheelSelectionBand: View {
    var height: CGFloat
    var cornerRadius: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Colors.surface.opacity(0.35))
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.selectionBorder, lineWidth: 1.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var index = 1
    ScreenBackground(glow: .topTrailing) {
        Wheel(
            values: Array(0..<5),
            selection: $index,
            label: { ["—", "Me lever", "Aller", "Faire", "Finir"][$0] }
        )
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
