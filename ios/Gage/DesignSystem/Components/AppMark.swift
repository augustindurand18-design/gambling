import SwiftUI

/// Marque de l'application : carte blanche arrondie portant la pastille
/// violette. Placeholder assume tant que l'icone definitive n'est pas dessinee.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
            .fill(Theme.Colors.surface)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .fill(Theme.Colors.brand)
                    .frame(width: size * 0.34, height: size * 0.34)
            }
            .shadow(color: Theme.Colors.ink.opacity(0.06), radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

#Preview {
    ScreenBackground { AppMark() }
}
