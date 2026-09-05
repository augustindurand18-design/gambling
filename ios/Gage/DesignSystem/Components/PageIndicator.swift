import SwiftUI

/// Points de progression d'un parcours en plusieurs etapes.
struct PageIndicator: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { position in
                // Les etapes franchies restent violettes ; la courante est
                // la plus grosse.
                let isCurrent = position == index
                let size: CGFloat = isCurrent ? 11 : 8
                Circle()
                    .fill(position <= index ? Theme.Colors.brand : Theme.Colors.dotInactive)
                    .frame(width: size, height: size)
            }
        }
        .animation(.easeOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Étape \(index + 1) sur \(count)")
    }
}

#Preview {
    ScreenBackground { PageIndicator(count: 4, index: 0) }
}
