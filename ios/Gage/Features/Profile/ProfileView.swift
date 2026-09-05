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

            Text("Tes défis te suivent sur tous tes appareils.")
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Theme.Spacing.small)
    }

    // MARK: - Sections

    private var engagement: some View {
        SettingsSection(title: "Ce que tu risques") {
            SettingsRow(
                symbol: "target",
                title: "Plafond par objectif",
                accessory: .value(Money.format(cents: BusinessRules.defaultPerGoalCapCents))
            )
            SettingsDivider()
            SettingsRow(
                symbol: "calendar",
                title: "Plafond mensuel",
                accessory: .value(Money.format(cents: BusinessRules.defaultMonthlyCapCents))
            )
            SettingsDivider()
            SettingsRow(symbol: "creditcard", title: "Moyen de paiement", accessory: .comingSoon)
            SettingsDivider()
            SettingsRow(
                symbol: "heart",
                title: "Part reversée à une association",
                accessory: .value("\(BusinessRules.charityBps / 100) %")
            )
            SettingsDivider()
            SettingsRow(symbol: "building.columns", title: "Association choisie", accessory: .comingSoon)
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
