import SwiftUI

/// Ce que l'application dit une fois la preuve partie.
///
/// L'utilisateur vient d'engager de l'argent : il doit apprendre le resultat
/// sur l'ecran ou il l'a joue, pas en revenant par hasard sur l'accueil.
/// L'attente reste donc ouverte tant que le serveur n'a pas tranche.
enum Verdict: Equatable {
    /// Le serveur n'a pas encore repondu.
    case pending
    case kept
    case failed
    /// Verdict incertain, parti en revue humaine.
    case review
    /// Le serveur met trop longtemps. On ne fait pas patienter indefiniment
    /// quelqu'un devant un ecran : on dit ce qu'on sait, c'est-a-dire que la
    /// preuve est bien arrivee.
    case tooLong

    /// Ce que l'etat de l'objectif dit du verdict.
    ///
    /// `hasLostStake` porte deja la liste des etats ou l'argent est parti :
    /// la redire ici la ferait diverger le jour ou elle changera.
    init(state: GoalState) {
        if state == .closedKept || state == .validated {
            self = .kept
        } else if state == .rejected || state.hasLostStake {
            self = .failed
        } else if state == .humanReview {
            self = .review
        } else {
            self = .pending
        }
    }
}

/// Ecran d'attente puis d'annonce du verdict.
struct VerdictView: View {
    let verdict: Verdict
    var onFinish: () -> Void

    /// Decale l'image horizontalement pour le refus.
    @State private var shake: CGFloat = 0
    @State private var showsConfetti = false

    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Spacer()

            symbol
                .offset(x: shake)

            Text(title)
                .font(Theme.Fonts.display)
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.center)

            Text(detail)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Spacing.medium)

            Spacer()

            if verdict != .pending {
                PrimaryButton(title: "Terminer", showsChevron: false, action: onFinish)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if showsConfetti { ConfettiView() } }
        .task(id: verdict) { await react() }
    }

    // MARK: - Symbole

    @ViewBuilder
    private var symbol: some View {
        switch verdict {
        case .pending:
            ProgressView()
                .controlSize(.large)
                .tint(Theme.Colors.brand)

        case .kept:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Colors.kept)

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Colors.failed)

        case .review:
            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.brand)

        case .tooLong:
            Image(systemName: "paperplane.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.brand)
        }
    }

    private var title: String {
        switch verdict {
        case .pending: "On vérifie…"
        case .kept: "C'est validé"
        case .failed: "Preuve refusée"
        case .review: "Un humain va regarder"
        case .tooLong: "Preuve envoyée"
        }
    }

    private var detail: String {
        switch verdict {
        // Le montant n'est pas rappele ici : l'utilisateur le connait, il
        // vient de l'engager, et le lui repeter au moment ou il le perd
        // ressemblerait a une punition.
        case .pending: "Quelques secondes, on regarde ta photo."
        case .kept: "Tu as tenu ta promesse. Rien ne t'est débité."
        case .failed: "Ta photo ne montre pas ce qui était promis. Ta mise sera prélevée."
        case .review: "Ta preuve demande un second regard. Tu seras prévenu de la décision."
        case .tooLong: "Elle est bien arrivée. Le résultat s'affichera sur l'accueil."
        }
    }

    // MARK: - Reactions

    private func react() async {
        switch verdict {
        case .kept:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(duration: 0.4)) { showsConfetti = true }

        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            // Trois allers-retours qui s'amortissent : un refus se sent, il
            // n'a pas besoin d'etre spectaculaire.
            for offset in [12.0, -10.0, 7.0, -4.0, 0.0] {
                withAnimation(.easeInOut(duration: 0.07)) { shake = offset }
                try? await Task.sleep(for: .milliseconds(70))
            }

        case .review, .tooLong:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)

        case .pending:
            break
        }
    }
}

/// Pluie de confettis, le temps d'une validation.
///
/// Dessinee a la main plutot qu'importee : une dependance pour vingt
/// rectangles qui tombent ne se justifie pas, et celle-ci s'arrete d'elle-meme.
private struct ConfettiView: View {
    private static let palette: [Color] = [
        Theme.Colors.brand, Theme.Colors.kept, Theme.Colors.attention,
    ]

    @State private var fallen = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<24, id: \.self) { index in
                    piece(index: index, in: proxy.size)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { fallen = true }
    }

    /// Un confetti. Extrait du corps de la vue : ecrit d'un seul tenant,
    /// l'expression depassait ce que le compilateur accepte de resoudre.
    private func piece(index: Int, in size: CGSize) -> some View {
        let seed = Double(index)
        let x: CGFloat = size.width * (0.08 + 0.84 * (seed / 23))
        let y: CGFloat = fallen ? size.height + 40 : -40
        let duration: Double = 1.6 + seed.truncatingRemainder(dividingBy: 5) * 0.18

        return Rectangle()
            .fill(Self.palette[index % Self.palette.count])
            .frame(width: 7, height: 11)
            .rotationEffect(.degrees(fallen ? seed * 47 : 0))
            .position(x: x, y: y)
            .animation(.easeIn(duration: duration).delay(seed * 0.03), value: fallen)
    }
}
