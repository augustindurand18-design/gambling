import SwiftUI

/// Marque de l'application : carte blanche arrondie portant le monogramme.
struct AppMark: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
            .fill(Theme.Colors.surface)
            .frame(width: size, height: size)
            .overlay {
                let mark = size * 0.58
                GageMark()
                    .stroke(Theme.Gradients.brand, style: GageMark.stroke(for: mark))
                    .frame(width: mark, height: mark)
            }
            .shadow(color: Theme.Colors.ink.opacity(0.06), radius: 12, y: 6)
            .accessibilityHidden(true)
    }
}

#Preview {
    ScreenBackground { AppMark() }
}
