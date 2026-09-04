import SwiftUI

/// Pastille d'acces au profil : meme pastille claire que le bouton de retour,
/// pour que les deux commandes rondes des en-tetes se ressemblent.
struct ProfileButton: View {
    /// Initiales de l'utilisateur. En leur absence, une silhouette.
    var initials: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let initials, !initials.isEmpty {
                    Text(initials)
                        .font(Theme.Fonts.badge)
                        .foregroundStyle(Theme.Colors.brand)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.brand)
                }
            }
            .frame(width: 40, height: 40)
            .background(Theme.Colors.card, in: .circle)
            .shadow(color: Theme.Colors.ink.opacity(0.06), radius: 8, y: 3)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil et réglages")
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        HStack(spacing: Theme.Spacing.medium) {
            ProfileButton {}
            ProfileButton(initials: "AD") {}
        }
    }
}
