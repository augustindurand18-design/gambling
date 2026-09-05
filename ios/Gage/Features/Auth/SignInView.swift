import SwiftUI

/// Connexion en deux temps : l'adresse, puis le code recu par e-mail.
///
/// Le meme ecran sert a creer un compte et a en retrouver un : cote serveur
/// c'est le meme appel, et demander a l'utilisateur de choisir entre
/// « s'inscrire » et « se connecter » l'obligerait a se souvenir s'il est
/// deja venu.
struct SignInView: View {

    private enum Step { case email, code }

    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    BackButton(action: back)
                    Spacer(minLength: 0)
                }

                Text(title)
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Colors.ink)
                    .padding(.top, Theme.Spacing.large)

                Text(detail)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Spacing.small + 4)

                field
                    .padding(.top, Theme.Spacing.large)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Fonts.cardSubtitle)
                        .foregroundStyle(Theme.Colors.failed)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Spacing.small + 2)
                }

                Spacer(minLength: Theme.Spacing.medium)

                PrimaryButton(
                    title: buttonTitle,
                    showsChevron: false,
                    isEnabled: isFormValid && !isWorking,
                    action: submit
                )

                if step == .code {
                    Button("Renvoyer un code", action: resend)
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.Colors.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.medium - 4)
                        .disabled(isWorking)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)

            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.brand)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Contenu selon l'etape

    private var title: String {
        step == .email ? "Ton adresse e-mail" : "Ton code"
    }

    private var detail: String {
        switch step {
        case .email:
            "On t'envoie un code à six chiffres. Pas de mot de passe à retenir."
        case .code:
            "Code envoyé à \(email). Il expire dans une heure."
        }
    }

    private var buttonTitle: String {
        step == .email ? "Recevoir un code" : "Se connecter"
    }

    @ViewBuilder
    private var field: some View {
        switch step {
        case .email:
            AppTextField(
                placeholder: "ton@email.fr",
                text: $email,
                keyboard: .emailAddress,
                textContentType: .emailAddress
            )
            .accessibilityIdentifier("email-field")

        case .code:
            AppTextField(
                placeholder: "000000",
                text: $code,
                keyboard: .numberPad,
                textContentType: .oneTimeCode,
                tracking: 8,
                isCentered: true
            )
            .accessibilityIdentifier("code-field")
        }
    }

    /// Validation volontairement large : le serveur reste juge de l'adresse,
    /// et un filtre trop strict ici rejetterait des adresses valides.
    private var isFormValid: Bool {
        switch step {
        case .email:
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            return trimmed.contains("@") && trimmed.count >= 5
        case .code:
            return code.trimmingCharacters(in: .whitespaces).count == 6
        }
    }

    // MARK: - Actions

    private func back() {
        if step == .code {
            step = .email
            code = ""
            errorMessage = nil
        } else {
            dismiss()
        }
    }

    private func submit() {
        switch step {
        case .email: send()
        case .code: verify()
        }
    }

    private func send() {
        run {
            try await AuthAPI.shared.sendCode(to: email)
            step = .code
        }
    }

    private func resend() {
        run {
            try await AuthAPI.shared.sendCode(to: email)
        }
    }

    /// Rien a faire de plus en cas de succes : l'ouverture de session est
    /// captee par `SessionStore`, qui bascule l'application sur l'accueil.
    private func verify() {
        run {
            try await AuthAPI.shared.verify(code: code, for: email)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview { SignInView() }
