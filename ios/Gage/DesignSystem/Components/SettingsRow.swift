import SwiftUI

/// Ligne de reglage : un symbole, un libelle, et a droite soit la valeur en
/// vigueur, soit un chevron.
///
/// Les reglages qui dependent d'une brique pas encore ecrite sont montres
/// mais annonces comme tels : les cacher laisserait croire que l'application
/// ne s'en occupe pas, les rendre cliquables mentirait.
struct SettingsRow: View {

    enum Accessory {
        /// Valeur en vigueur, affichee telle quelle.
        case value(String)
        /// Mene vers un ecran.
        case link
        /// Prevu, pas encore disponible.
        case comingSoon
    }

    let symbol: String
    let title: String
    var accessory: Accessory = .link
    /// Une action destructrice se signale par sa couleur et son libelle.
    var isDestructive: Bool = false
    var action: (() -> Void)?

    private var isActionable: Bool {
        if case .comingSoon = accessory { return false }
        return action != nil
    }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDestructive ? Theme.Colors.failed : Theme.Colors.inkMuted)
                    .frame(width: 24)

                Text(title)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(isDestructive ? Theme.Colors.failed : Theme.Colors.ink)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: Theme.Spacing.small)

                accessoryView
            }
            .padding(.horizontal, Theme.Spacing.medium - 4)
            .frame(minHeight: Theme.Metrics.cardHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .value(let text):
            Text(text)
                .font(Theme.Fonts.footnoteEmphasis)
                .foregroundStyle(Theme.Colors.inkMuted)

        case .link:
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.placeholderBorder)

        case .comingSoon:
            Text("Bientôt")
                .font(Theme.Fonts.badge)
                .foregroundStyle(Theme.Colors.inkFaded)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.Colors.disabledFill, in: .capsule)
        }
    }
}

/// Regroupement de lignes de reglage sous un intitule.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(title.uppercased())
                .font(Theme.Fonts.sectionLabel)
                .tracking(1.4)
                .foregroundStyle(Theme.Colors.inkMuted)
                .padding(.horizontal, Theme.Spacing.small - 4)

            VStack(spacing: 0) {
                content
            }
            .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        }
    }
}

/// Filet entre deux lignes, aligne sur le texte et non sur le symbole.
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Theme.Colors.divider)
            .padding(.leading, Theme.Spacing.medium - 4 + 24 + 14)
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        SettingsSection(title: "Ton engagement") {
            SettingsRow(symbol: "eurosign.circle", title: "Plafond par objectif", accessory: .value("100 €"))
            SettingsDivider()
            SettingsRow(symbol: "creditcard", title: "Moyen de paiement", accessory: .comingSoon)
            SettingsDivider()
            SettingsRow(symbol: "heart", title: "Association") {}
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
