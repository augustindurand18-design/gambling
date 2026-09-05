import SwiftUI

/// Champ de saisie de la charte : fond clair, contour discret qui se teinte
/// quand le champ a le focus.
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType?
    /// Espacement des caracteres, pour les codes a saisir chiffre par chiffre.
    var tracking: CGFloat = 0
    var isCentered: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(Theme.Fonts.option)
            .tracking(tracking)
            .foregroundStyle(Theme.Colors.ink)
            .multilineTextAlignment(isCentered ? .center : .leading)
            .keyboardType(keyboard)
            .textContentType(textContentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFocused)
            .padding(.horizontal, Theme.Spacing.medium - 4)
            .frame(height: Theme.Metrics.cardHeight + 4)
            .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.Colors.brand : Theme.Colors.divider,
                        lineWidth: 1.5
                    )
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

#Preview {
    @Previewable @State var email = ""
    @Previewable @State var code = ""
    ScreenBackground(glow: .topTrailing) {
        VStack(spacing: Theme.Spacing.medium) {
            AppTextField(placeholder: "ton@email.fr", text: $email, keyboard: .emailAddress)
            AppTextField(placeholder: "000000", text: $code, keyboard: .numberPad, tracking: 8, isCentered: true)
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
