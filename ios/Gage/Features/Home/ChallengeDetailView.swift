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
    /// Demande d'ouvrir la capture. La fiche ne presente pas l'ecran
    /// elle-meme : elle est deja une feuille modale, et en empiler une
    /// seconde par-dessus ne marche pas. L'accueil s'en charge une fois
    /// celle-ci refermee.
    var onCapture: ((PendingProof) -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// Rafraichi chaque seconde, uniquement quand une fenetre est ouverte.
    @State private var now = Date.now

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScreenBackground(glow: .topTrailing) {
                ScrollView {
                    VStack(spacing: Theme.Spacing.medium + 4) {
                        headline
                        if isWindowOpen { openWindow }
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
            .onReceive(tick) { if isWindowOpen { now = $0 } }
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

    /// Seance dont la fenetre est ouverte, s'il y en a une.
    ///
    /// C'est elle qu'il faut, et non le defi : `ChallengeSummary.id` est
    /// l'identifiant de la **promesse** hebdomadaire, pas d'un objectif. La
    /// base range « me lever 3 fois cette semaine » en trois objectifs, qui
    /// sont dans `sessions` — envoyer l'identifiant du groupe a
    /// `submit_proof` la fait repondre « Objectif introuvable ».
    ///
    /// L'echeance vient du defi : elle est le minimum des echeances du
    /// groupe, et seule une seance ouverte en porte une.
    private var openSession: (goalID: UUID, deadline: Date)? {
        guard let session = challenge.sessions.first(where: { $0.state == .proofWindowOpen }),
              let deadline = challenge.deadline
        else { return nil }
        return (session.id, deadline)
    }

    private var isWindowOpen: Bool { openSession != nil }

    /// Fenetre ouverte : le temps qui reste, et de quoi la saisir.
    ///
    /// C'est le seul endroit de la fiche ou une echeance s'affiche. Pour un
    /// objectif encore `committed`, l'instant du controle n'appartient pas au
    /// telephone (invariant 4) — ici il est deja connu, l'utilisateur vient
    /// d'etre prevenu.
    @ViewBuilder
    private var openWindow: some View {
        if let open = openSession {
            let deadline = open.deadline
            let remaining = ProofWindow.remaining(until: deadline, now: now)

            VStack(spacing: Theme.Spacing.small + 2) {
                Text(remaining == nil ? "Temps écoulé" : "Il te reste")
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.inkMuted)

                Text(ProofWindow.countdown(until: deadline, now: now))
                    .font(Theme.Fonts.stat)
                    .monospacedDigit()
                    .foregroundStyle(remaining == nil ? Theme.Colors.failed : Theme.Colors.brand)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Temps restant pour envoyer ta preuve")

                if remaining == nil {
                    // Le bouton disparait, le texte reste. Le serveur reste
                    // seul juge de ce qui est encore recevable : on n'annonce
                    // pas ici que la mise est perdue.
                    Text("La fenêtre s'est refermée. Ta mise sera prélevée.")
                        .font(Theme.Fonts.calendarLegend)
                        .foregroundStyle(Theme.Colors.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    PrimaryButton(title: "Prendre la photo", showsChevron: false) {
                        onCapture?(PendingProof(goalID: open.goalID, deadline: deadline))
                        dismiss()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.Colors.card)
            )
        }
    }

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
