import SwiftUI

/// Profil et reglages.
///
/// L'ecran commence par ce qui expose l'utilisateur financierement — ses
/// plafonds, sa carte, ce que devient une mise perdue — avant les reglages de
/// confort. C'est aussi la que doivent se lire les engagements pris envers
/// lui : part reversee, duree de conservation des photos, version des CGU
/// acceptee.
struct ProfileView: View {
    let assiduity: AssiduityStatus

    @Environment(\.dismiss) private var dismiss

    /// Etat du compte, charge au premier affichage. Nul tant qu'il n'est pas
    /// arrive : les lignes affichent alors leur libelle d'attente plutot
    /// qu'une valeur inventee.
    @State private var account: AccountState?
    @State private var isEnrollingCard = false
    @State private var isChoosingCharity = false
    @State private var charityName: String?

    var body: some View {
        NavigationStack {
            ScreenBackground(glow: .topTrailing) {
                ScrollView {
                    VStack(spacing: Theme.Spacing.medium + 4) {
                        identity
                        engagement
                        subscription
                        preferences
                        privacy
                        footer
                    }
                    .padding(.horizontal, Theme.Spacing.screenHorizontal)
                    .padding(.top, Theme.Spacing.small)
                    .padding(.bottom, Theme.Spacing.large)
                }
                .scrollIndicators(.hidden)
            }
            .task { await loadAccount() }
            .sheet(isPresented: $isEnrollingCard) {
                CardEnrollmentView(
                    onEnrolled: { Task { await loadAccount() } },
                    onSkip: nil,
                    replacesExistingCard: account?.hasCard ?? false
                )
            }
            .sheet(isPresented: $isChoosingCharity) {
                CharityPickerView { _ in Task { await loadAccount() } }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.Colors.brand)
                }
            }
        }
    }

    // MARK: - Identite

    private var identity: some View {
        VStack(spacing: Theme.Spacing.small + 2) {
            Image(systemName: "person.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.Colors.brand)
                .frame(width: 72, height: 72)
                .background(Theme.Colors.card, in: .circle)
                .shadow(color: Theme.Colors.ink.opacity(0.06), radius: 10, y: 4)

            Text(AuthAPI.shared.currentEmail ?? "Compte connecté")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Tes objectifs te suivent sur tous tes appareils.")
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.small)
    }

    /// « Visa •••• 4242 », ou l'invitation a en enregistrer une.
    private var cardLabel: String {
        account?.cardLabel ?? "…"
    }

    private var charityLabel: String {
        guard account != nil else { return "…" }
        return charityName ?? "À choisir"
    }

    private func loadAccount() async {
        #if DEBUG
        if SessionStore.isUITesting { return }
        #endif
        account = try? await ProfileAPI.shared.load()
        if let id = account?.defaultCharityID {
            charityName = try? await ProfileAPI.shared.charities().first { $0.id == id }?.name
        } else {
            charityName = nil
        }
    }

    // MARK: - Sections

    private var engagement: some View {
        SettingsSection(title: "Ce que tu risques") {
            SettingsRow(
                symbol: "target",
                title: "Plafond par objectif",
                accessory: .value(Money.format(cents: account?.perGoalCapCents ?? BusinessRules.defaultPerGoalCapCents))
            )
            SettingsDivider()
            SettingsRow(
                symbol: "calendar",
                title: "Plafond mensuel",
                accessory: .value(Money.format(cents: account?.monthlyCapCents ?? BusinessRules.defaultMonthlyCapCents))
            )
            SettingsDivider()
            SettingsRow(
                symbol: "creditcard",
                title: "Moyen de paiement",
                accessory: .value(cardLabel)
            ) {
                // Ouvert meme si le compte n'est pas encore charge : c'est une
                // action legitime, et la refuser empecherait quelqu'un hors
                // ligne d'enregistrer sa carte. C'est l'affichage qui devait
                // cesser de mentir, pas l'acces.
                isEnrollingCard = true
            }
            SettingsDivider()
            SettingsRow(
                symbol: "heart",
                title: "Part reversée à une association",
                accessory: .value("\(BusinessRules.charityBps / 100) %")
            )
            SettingsDivider()
            SettingsRow(
                symbol: "building.columns",
                title: "Association choisie",
                accessory: .value(charityLabel)
            ) {
                isChoosingCharity = true
            }
        }
    }

    private var subscription: some View {
        SettingsSection(title: "Abonnement") {
            SettingsRow(
                symbol: "tag",
                title: "Tarif en cours",
                accessory: .value(assiduity.isDiscountEarned ? "5 €/mois" : "25 €/mois")
            )
            SettingsDivider()
            SettingsRow(
                symbol: "flame",
                title: "Objectifs tenus cette semaine",
                accessory: .value("\(assiduity.keptThisWeek) / \(assiduity.threshold)")
            )
            SettingsDivider()
            SettingsRow(symbol: "arrow.triangle.2.circlepath", title: "Gérer l'abonnement", accessory: .comingSoon)
        }
    }

    private var preferences: some View {
        SettingsSection(title: "Réglages") {
            SettingsRow(symbol: "bell", title: "Notifications", accessory: .comingSoon)
            SettingsDivider()
            SettingsRow(symbol: "clock.arrow.circlepath", title: "Historique et reçus", accessory: .comingSoon)
            SettingsDivider()
            SettingsRow(symbol: "questionmark.circle", title: "Aide") {
                Log.app.debug("Profil : aide")
            }
            SettingsDivider()
            SettingsRow(symbol: "rectangle.portrait.and.arrow.right", title: "Se déconnecter") {
                // L'ecran se ferme de lui-meme : `SessionStore` capte la fin
                // de session et ramene l'application sur l'accueil.
                Task { try? await AuthAPI.shared.signOut() }
            }
        }
    }

    private var privacy: some View {
        SettingsSection(title: "Tes données") {
            SettingsRow(
                symbol: "photo.badge.checkmark",
                title: "Conservation des photos",
                accessory: .value("\(BusinessRules.proofRetentionDays) jours")
            )
            SettingsDivider()
            SettingsRow(
                symbol: "doc.text",
                title: "Conditions acceptées",
                accessory: .value(AppConfig.termsVersion)
            )
            SettingsDivider()
            SettingsRow(symbol: "square.and.arrow.down", title: "Télécharger mes données", accessory: .comingSoon)
            SettingsDivider()
            SettingsRow(
                symbol: "trash",
                title: "Supprimer mon compte",
                accessory: .comingSoon,
                isDestructive: true
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Gage \(AppConfig.appVersion) (\(AppConfig.buildNumber))")
            Text("Les photos sont prises dans l'app, jamais importées.")
        }
        .font(Theme.Fonts.calendarLegend)
        .foregroundStyle(Theme.Colors.inkMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ProfileView(assiduity: AssiduityStatus(keptThisWeek: 2))
}
