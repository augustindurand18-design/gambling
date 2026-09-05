import SwiftUI

/// Fiche d'un defi : la promesse, les seances de la semaine, ce qui est en
/// jeu et ce qu'il faudra montrer.
///
/// Meme forme que le profil — feuille modale, sections posees sur le fond
/// degrade — parce que c'est la meme nature d'ecran : on vient y lire l'etat
/// des choses, pas y agir.
///
/// Ce qui n'y figure pas est aussi voulu : l'instant du controle surprise
/// n'est jamais affiche, il n'appartient pas au telephone.
struct ChallengeDetailView: View {
    let challenge: ChallengeSummary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenBackground(glow: .topTrailing) {
                ScrollView {
                    VStack(spacing: Theme.Spacing.medium + 4) {
                        headline
                        sessions
                        stake
                        proof
                        footer
                    }
                    .padding(.horizontal, Theme.Spacing.screenHorizontal)
                    .padding(.top, Theme.Spacing.small)
                    .padding(.bottom, Theme.Spacing.large)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Ton défi")
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

    // MARK: - Promesse

    private var headline: some View {
        VStack(spacing: Theme.Spacing.small + 2) {
            StateBadge(state: challenge.state)

            Text(challenge.title)
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(progressText)
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Spacing.small)
    }

    private var progressText: String {
        guard challenge.sessionCount > 0 else { return "Aucune séance programmée." }
        return "\(challenge.keptCount) séance\(challenge.keptCount > 1 ? "s" : "") tenue\(challenge.keptCount > 1 ? "s" : "") sur \(challenge.sessionCount)."
    }

    // MARK: - Sections

    private var sessions: some View {
        SettingsSection(title: "Tes séances") {
            ForEach(Array(challenge.sessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 { SettingsDivider() }
                SettingsRow(
                    symbol: Self.symbol(for: session.state),
                    title: Self.dayText(session.date),
                    accessory: .value(session.timeText ?? "Le matin même")
                )
            }
        }
    }

    private var stake: some View {
        SettingsSection(title: "Ce que tu risques") {
            SettingsRow(
                symbol: "eurosign.circle",
                title: "La mise, pour la semaine",
                accessory: .value(
                    challenge.stakeCents > 0
                        ? Money.format(cents: challenge.stakeCents)
                        : "Rien encore"
                )
            )
            SettingsDivider()
            SettingsRow(
                symbol: "heart",
                title: "Part reversée à une association",
                accessory: .value("\(BusinessRules.charityBps / 100) %")
            )
        }
    }

    private var proof: some View {
        SettingsSection(title: "Ce que tu montreras") {
            SettingsRow(symbol: "camera", title: challenge.proofTitle, accessory: .value(""))
            SettingsDivider()
            SettingsRow(
                symbol: "bell",
                title: "Quand",
                accessory: .value(challenge.deadline == nil ? "Prévenu le jour même" : "Fenêtre ouverte")
            )
        }
    }

    private var footer: some View {
        Text("Tant que le paiement n'est pas branché, ce défi reste un brouillon : aucune mise n'est engagée et rien ne peut être débité.")
            .font(Theme.Fonts.calendarLegend)
            .foregroundStyle(Theme.Colors.inkMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Mise en forme

    /// L'etat de la seance se lit d'abord au symbole : une pastille de
    /// couleur seule ne se distingue pas pour tout le monde.
    private static func symbol(for state: GoalState) -> String {
        switch state {
        case .closedKept, .validated, .chargeOk: "checkmark.circle"
        case .closedFailed, .rejected, .chargeFailed, .chargePending: "xmark.circle"
        case .proofWindowOpen: "camera.circle"
        default: "calendar"
        }
    }

    /// « Lundi 7 septembre ».
    private static func dayText(_ date: Date) -> String {
        let text = dayFormatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Money.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()
}

#Preview {
    ChallengeDetailView(
        challenge: ChallengeSummary(
            id: UUID(),
            title: "Aller à la salle 3 fois cette semaine",
            proofTitle: "Photo sur place — Confirme que tu es bien à la salle",
            state: .draft,
            stakeCents: 0,
            deadline: nil,
            sessions: [
                ChallengeSession(id: UUID(), date: .now, state: .draft, timeText: "18 h 30"),
                ChallengeSession(id: UUID(), date: .now.addingTimeInterval(172_800), state: .draft, timeText: nil),
                ChallengeSession(id: UUID(), date: .now.addingTimeInterval(345_600), state: .draft, timeText: "10 h 00")
            ]
        )
    )
}
