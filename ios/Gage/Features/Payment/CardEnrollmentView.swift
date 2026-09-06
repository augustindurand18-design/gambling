import PassKit
import StripePaymentSheet
import SwiftUI

/// Enregistrement de la carte, une seule fois.
///
/// La carte va de ce formulaire à Stripe directement. Notre serveur ne la voit
/// jamais et n'en garde que quatre chiffres, pour que l'utilisateur sache
/// laquelle sera débitée.
///
/// La 3DS est demandée **ici**, au calme, et pas au moment d'un débit. C'est
/// tout l'intérêt du `usage: off_session` posé sur le SetupIntent : le jour
/// d'un objectif raté, il n'y a plus personne devant le téléphone.
struct CardEnrollmentView: View {
    /// Appelé quand une carte est effectivement enregistrée.
    var onEnrolled: () -> Void
    /// Nul quand l'écran s'ouvre depuis l'onboarding, où l'on ne renonce pas.
    var onSkip: (() -> Void)?

    @State private var phase: Phase = .loading
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case ready(PaymentSheet)
        case failed(String)
        case done
    }

    var body: some View {
        ScreenBackground {
            VStack(spacing: Theme.Spacing.large) {
                header
                Spacer(minLength: 0)
                content
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.vertical, Theme.Spacing.large)
        }
        .task { await prepare() }
    }

    // MARK: - Entête

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Ta carte")
                .font(Theme.Fonts.display)
                .foregroundStyle(Theme.Colors.ink)

            Text(
                "Elle est enregistrée une seule fois. Tu ne la ressaisiras jamais, "
                    + "et rien n'est prélevé maintenant."
            )
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Colors.inkMuted)
            .fixedSize(horizontal: false, vertical: true)

            reassurance
                .padding(.top, Theme.Spacing.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Ce que l'utilisateur a besoin de savoir avant de donner sa carte. Dit
    /// ici plutôt que dans des conditions générales : c'est le moment où la
    /// question se pose.
    private var reassurance: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            point("Rien n'est débité tant qu'un objectif n'est pas manqué.")
            point("Tu fixes toi-même le montant de chaque mise, et tes plafonds.")
            point("Un objectif refusé se conteste pendant 48 heures.")
        }
        .padding(Theme.Spacing.medium - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.small) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Colors.kept)
                .padding(.top, 3)
            Text(text)
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        VStack(spacing: Theme.Spacing.small) {
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.failed)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.brand)
                    .frame(height: Theme.Metrics.cardHeight)

            case .ready(let sheet):
                PaymentSheet.PaymentButton(
                    paymentSheet: sheet,
                    onCompletion: handle
                ) {
                    PrimaryButtonLabel(title: "Enregistrer ma carte")
                }
                .accessibilityIdentifier("card-enroll")

            case .failed:
                PrimaryButton(title: "Réessayer", showsChevron: false) {
                    Task { await prepare() }
                }

            case .done:
                Label("Carte enregistrée", systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.kept)
                    .frame(height: Theme.Metrics.cardHeight)
            }

            if let onSkip, !isDone {
                Button("Plus tard") {
                    onSkip()
                    dismiss()
                }
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
            }
        }
    }

    private var isDone: Bool {
        if case .done = phase { return true }
        return false
    }

    // MARK: - Stripe

    private func prepare() async {
        phase = .loading
        errorMessage = nil

        do {
            let session = try await PaymentAPI.shared.setupSession()

            // La clé publiable vient du serveur, pas de la configuration
            // locale : elle doit provenir du compte Stripe qui vient de créer
            // ce SetupIntent. Une clé dépareillée — ou absente du fichier
            // local d'un poste — ne se voyait qu'ici, sur un message
            // générique en anglais, au moment précis où l'on demande une
            // carte. La valeur locale ne sert plus que de secours.
            if let key = session.publishableKey ?? AppConfig.stripePublishableKey {
                STPAPIClient.shared.publishableKey = key
            } else {
                throw AppError.server(
                    message: "Le service de paiement n'est pas configuré. "
                        + "Préviens-nous, il n'y a rien à faire de ton côté."
                )
            }

            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "Gage"
            configuration.customer = .init(
                id: session.customerID,
                ephemeralKeySecret: session.ephemeralKey
            )
            // Sans URL de retour, une authentification 3DS qui passe par une
            // application bancaire ne sait pas comment revenir ici.
            configuration.returnURL = "gage://stripe-redirect"
            configuration.allowsDelayedPaymentMethods = false
            configuration.applePay = Self.applePayConfiguration()

            phase = .ready(
                PaymentSheet(
                    setupIntentClientSecret: session.setupIntentClientSecret,
                    configuration: configuration
                )
            )
        } catch {
            let message = (error as? AppError)?.errorDescription
                ?? "Impossible de préparer l'enregistrement."
            phase = .failed(message)
            errorMessage = message
        }
    }

    // MARK: - Apple Pay

    /// Apple Pay, mais seulement s'il peut être déclaré comme paiement différé.
    ///
    /// Ce n'est pas un scrupule de forme. Apple Pay n'enregistre pas un numéro
    /// de carte mais un jeton propre à l'appareil, et tout Gage repose sur un
    /// débit `off_session` déclenché des jours plus tard, sans personne devant
    /// le téléphone. Apple demande que cette intention soit annoncée à
    /// l'enregistrement, via `PKDeferredPaymentRequest` ; sans elle, le
    /// prélèvement ultérieur peut être refusé.
    ///
    /// Un tel refus serait invisible ici et n'apparaîtrait qu'au seul moment
    /// qui compte, celui où quelqu'un a raté son objectif. On préfère donc ne
    /// pas proposer Apple Pay du tout tant que la page de gestion — exigée par
    /// Apple pour cette déclaration — n'existe pas. C'est l'invariant 2 :
    /// jamais de débit sur un doute.
    private static func applePayConfiguration() -> PaymentSheet.ApplePayConfiguration? {
        guard let managementURL = AppConfig.paymentManagementURL else {
            Log.payment.notice(
                "Apple Pay non proposé : GagePaymentManagementURL absente"
            )
            return nil
        }

        // Le montant exact n'est pas connu à l'enregistrement — il dépend des
        // objectifs à venir. On annonce donc le plafond par objectif, qui est
        // le maximum possible par conception.
        let ceiling = NSDecimalNumber(value: Double(BusinessRules.defaultPerGoalCapCents) / 100)

        return .init(
            merchantId: AppConfig.appleMerchantID,
            merchantCountryCode: "FR",
            customHandlers: .init(paymentRequestHandler: { request in
                let billing = PKDeferredPaymentSummaryItem(
                    label: "Mise maximale par objectif",
                    amount: ceiling
                )
                // Une date est obligatoire. Le débit réel survient à l'échéance
                // d'un objectif ; la semaine est le cycle du produit.
                billing.deferredDate = Date().addingTimeInterval(7 * 24 * 3600)

                request.deferredPaymentRequest = PKDeferredPaymentRequest(
                    paymentDescription:
                        "Mise engagée sur tes objectifs. Débitée uniquement si un objectif est manqué.",
                    deferredBilling: billing,
                    managementURL: managementURL
                )
                return request
            })
        )
    }

    private func handle(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            // Le profil est mis à jour par le webhook `setup_intent.succeeded`,
            // pas ici : une confirmation côté application peut se perdre, et
            // c'est le serveur qui doit faire foi sur ce qui autorise un débit.
            phase = .done
            Log.payment.info("Carte enregistrée")
            onEnrolled()

        case .canceled:
            break

        case .failed(let error):
            errorMessage = error.localizedDescription
            Log.payment.error("Enregistrement de carte: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Habillage du bouton Stripe avec l'apparence de l'application.
///
/// `PaymentSheet.PaymentButton` impose son propre conteneur : on lui donne le
/// contenu, pas le bouton entier.
private struct PrimaryButtonLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Fonts.cardTitle)
            .foregroundStyle(Theme.Colors.onBrand)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.cardHeight)
            .background(Theme.Gradients.brand, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }
}
