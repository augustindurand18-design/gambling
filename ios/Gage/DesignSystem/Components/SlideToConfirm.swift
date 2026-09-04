import SwiftUI

/// Curseur a faire glisser pour confirmer un engagement.
///
/// Un bouton se tape par reflexe ; ce geste-la, non. C'est ce qu'on veut au
/// moment ou l'utilisateur accepte qu'une somme puisse etre prelevee : le
/// consentement doit couter un mouvement volontaire, impossible a declencher
/// d'un doigt qui trainait sur l'ecran.
struct SlideToConfirm: View {
    let title: String
    /// Libelle affiche tant que le geste n'est pas autorise.
    var disabledTitle: String
    var isEnabled: Bool = true
    let onConfirm: () -> Void

    @State private var offset: CGFloat = 0

    private let inset: CGFloat = 5
    private var knob: CGFloat { Theme.Metrics.slideKnob }
    private var track: CGFloat { Theme.Metrics.slideTrack }

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = max(0, geometry.size.width - knob - inset * 2)
            let progress = maxOffset > 0 ? offset / maxOffset : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isEnabled ? Theme.Colors.cardSelected : Theme.Colors.disabledFill)
                    .overlay {
                        Capsule().strokeBorder(
                            isEnabled ? Theme.Colors.brand.opacity(0.35) : .clear,
                            lineWidth: 1.5
                        )
                    }

                Text(isEnabled ? title : disabledTitle)
                    .font(Theme.Fonts.button)
                    .foregroundStyle(isEnabled ? Theme.Colors.brand : Theme.Colors.inkFaded)
                    .frame(maxWidth: .infinity)
                    .opacity(isEnabled ? max(0, 1 - progress * 1.8) : 1)
                    .allowsHitTesting(false)

                if isEnabled {
                    knobView
                        .offset(x: inset + offset)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    offset = min(max(0, value.translation.width), maxOffset)
                                }
                                .onEnded { _ in
                                    // Le seuil est haut : un glissement timide
                                    // revient en arriere plutot que d'engager.
                                    if offset >= maxOffset * 0.9 {
                                        offset = maxOffset
                                        onConfirm()
                                    } else {
                                        withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                    }
                                }
                        )
                }
            }
        }
        .frame(height: track)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { offset = 0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isEnabled ? title : disabledTitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { onConfirm() } }
    }

    private var knobView: some View {
        Circle()
            .fill(Theme.Gradients.brand)
            .frame(width: knob, height: knob)
            .overlay {
                Image(systemName: "arrow.right")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.Colors.onBrand)
            }
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        VStack(spacing: Theme.Spacing.medium) {
            SlideToConfirm(
                title: "Glisse pour t'engager",
                disabledTitle: "Signe pour débloquer",
                isEnabled: true
            ) {}
            SlideToConfirm(
                title: "Glisse pour t'engager",
                disabledTitle: "Signe pour débloquer",
                isEnabled: false
            ) {}
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
