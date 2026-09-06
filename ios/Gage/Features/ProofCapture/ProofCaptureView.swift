import SwiftUI

/// Écran de preuve : le viseur, le compte à rebours, l'envoi.
///
/// Il n'y a volontairement aucun moyen d'importer une image : le seul bouton
/// prend une photo (invariant 5). Et aucune confirmation avant l'envoi — la
/// fenêtre dure quinze minutes, une étape de plus, c'est une mise perdue pour
/// un écran de trop.
struct ProofCaptureView: View {
    let pending: PendingProof
    var onFinished: () -> Void

    @State private var camera = CameraSession()
    /// Photo reellement capturee, affichee des qu'elle existe.
    ///
    /// Le viseur en direct continuait de tourner pendant l'envoi : rien ne
    /// confirmait que la photo etait prise, et l'ecran montrait autre chose
    /// que ce qui partait. Sur un ecran ou une mise est en jeu, l'utilisateur
    /// doit voir exactement ce qu'il envoie.
    @State private var captured: UIImage?
    @State private var phase: Phase = .framing
    @State private var now = Date.now
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case framing
        case sending
        /// Preuve deposee, verdict attendu.
        case awaiting(Verdict)
        case failed(String)
    }

    /// Rythme et duree de l'attente du verdict.
    ///
    /// Deux secondes entre deux questions : le serveur tranche en trois a dix
    /// secondes, interroger plus vite ne ferait que multiplier les requetes.
    /// Au-dela de quarante secondes on cesse d'attendre — laisser quelqu'un
    /// devant une roue qui tourne indefiniment est pire que de lui dire qu'on
    /// ne sait pas encore.
    private static let pollInterval = Duration.seconds(2)
    private static let pollTimeout = Duration.seconds(40)

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScreenBackground {
            VStack(spacing: Theme.Spacing.medium) {
                if case .awaiting(let verdict) = phase {
                    // Plus de viseur ni de compte a rebours : la preuve est
                    // partie, il n'y a plus qu'un resultat a attendre.
                    VerdictView(verdict: verdict) { finish() }
                } else {
                    header
                    viewfinder
                    action
                }
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.vertical, Theme.Spacing.medium)
        }
        .task {
            await camera.start()
        }
        .onDisappear {
            camera.stop()
        }
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Entête

    private var header: some View {
        VStack(spacing: Theme.Spacing.small) {
            Text("Envoie ta preuve")
                .font(Theme.Fonts.display)
                .foregroundStyle(Theme.Colors.ink)

            if let deadline = pending.deadline {
                Text(ProofWindow.countdown(until: deadline, now: now))
                    .font(Theme.Fonts.stat)
                    .monospacedDigit()
                    .foregroundStyle(
                        ProofWindow.remaining(until: deadline, now: now) == nil
                            ? Theme.Colors.failed
                            : Theme.Colors.brand
                    )
                    .contentTransition(.numericText())
                    .accessibilityLabel("Temps restant")
            } else {
                Text("Prends la photo maintenant.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
            }
        }
    }

    // MARK: - Viseur

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            if let captured {
                Image(uiImage: captured)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Photo envoyée")
            } else {
                switch camera.state {
                case .ready:
                    #if targetEnvironment(simulator)
                    simulatorPlaceholder
                    #else
                    CameraPreview(session: camera.session)
                    #endif

                case .denied:
                    message(
                        "L'accès à l'appareil photo est refusé.",
                        detail: "Une preuve ne peut être prise que dans l'application. Autorise la caméra dans les Réglages."
                    )

                case .unavailable(let reason):
                    message("Caméra indisponible", detail: reason)

                case .idle:
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.Colors.brand)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(.rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.Colors.placeholderBorder, lineWidth: 1)
        }
    }

    #if targetEnvironment(simulator)
    private var simulatorPlaceholder: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.inkMuted)
            Text("Simulateur")
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.ink)
            Text("Une image de développement sera envoyée.")
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.card)
    }
    #endif

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: Theme.Spacing.small) {
            Text(title)
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(Theme.Colors.ink)
            Text(detail)
                .font(Theme.Fonts.cardSubtitle)
                .foregroundStyle(Theme.Colors.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.card)
    }

    // MARK: - Action

    @ViewBuilder
    private var action: some View {
        switch phase {
        case .framing:
            PrimaryButton(title: "Prendre la photo", showsChevron: false) {
                Task { await send() }
            }
            .disabled(camera.state != .ready)
            .accessibilityIdentifier("proof-capture")

        case .sending:
            HStack(spacing: Theme.Spacing.small) {
                ProgressView().tint(Theme.Colors.brand)
                Text("Envoi de ta preuve…")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.medium)

        // `awaiting` n'a pas de barre d'action : `VerdictView` occupe tout
        // l'ecran et porte son propre bouton.
        case .awaiting:
            EmptyView()

        case .failed(let message):
            VStack(spacing: Theme.Spacing.small) {
                Text(message)
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.failed)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Réessayer", showsChevron: false) {
                    Task { await retry() }
                }

                Button("Fermer") { finish() }
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkMuted)
            }
        }
    }

    // MARK: - Envoi

    private func send() async {
        phase = .sending

        do {
            // L'instant de prise de vue est déclaré par l'appareil, donc non
            // fiable — le serveur le sait et fait foi sur `server_received_at`.
            // On l'envoie quand même : l'écart entre les deux est précisément
            // ce que l'anti-triche mesure.
            let capturedAt = Date.now
            let jpeg = try await camera.capture(goalID: pending.goalID)

            // Fige l'ecran sur ce qui part, avant meme le pre-filtre : c'est
            // l'instant ou l'utilisateur doit voir sa photo, pas apres
            // l'envoi. La camera n'a plus rien a filmer.
            captured = UIImage(data: jpeg)
            camera.stop()

            // Le pré-filtre ne bloque jamais l'envoi : son résultat accompagne
            // la preuve, il ne la juge pas.
            let precheck = await ProofVisionAnalyzer.analyze(jpegData: jpeg)

            // Sans EXIF, l'anti-triche serveur lève un signal et la preuve part
            // en revue humaine. C'est le comportement voulu — une photo prise
            // par un appareil en produit toujours — mais ça veut dire qu'un
            // oubli ici coûte 0,20 à 0,50 € par preuve.
            let exif = ProofExif.extract(from: jpeg)

            try await ProofsAPI.shared.submit(
                goalID: pending.goalID,
                jpegData: jpeg,
                capturedAt: capturedAt,
                precheck: precheck,
                exif: exif
            )

            phase = .awaiting(.pending)
            await awaitVerdict()
        } catch {
            // Le repli generique efface l'information au moment ou elle est
            // la plus utile : une erreur qui n'est pas un `AppError` vient de
            // la camera ou du SDK, et son texte est la seule chose qui
            // distingue une panne d'objectif d'un refus du serveur. On la
            // journalise toujours, et on la montre en developpement — jamais
            // a un utilisateur, a qui elle ne dirait rien.
            Log.proof.error("Envoi de la preuve: \(String(describing: error), privacy: .public)")

            if let appError = error as? AppError, let description = appError.errorDescription {
                phase = .failed(description)
            } else {
                #if DEBUG
                phase = .failed("Ta preuve n'a pas pu être envoyée.\n\n\(error)")
                #else
                phase = .failed("Ta preuve n'a pas pu être envoyée.")
                #endif
            }
        }
    }

    /// Interroge le serveur jusqu'au verdict.
    ///
    /// L'utilisateur vient d'engager de l'argent : le renvoyer a l'accueil
    /// sans reponse, alors que le verdict tombe en quelques secondes, lui
    /// ferait chercher lui-meme ce qu'on peut lui dire tout de suite.
    ///
    /// Une erreur reseau n'interrompt pas l'attente : la preuve est deja
    /// deposee, et l'echec d'une lecture ne change rien a ce que le serveur
    /// decidera. On retente au tour suivant.
    private func awaitVerdict() async {
        let deadline = ContinuousClock.now + Self.pollTimeout

        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { return }

            guard let state = try? await GoalsAPI.shared.state(of: pending.goalID) else {
                continue
            }

            let verdict = Verdict(state: state)
            if verdict != .pending {
                phase = .awaiting(verdict)
                return
            }
        }

        // Le serveur n'a pas tranche a temps. On ne prétend pas savoir : la
        // seule chose certaine est que la preuve est arrivee.
        phase = .awaiting(.tooLong)
    }

    /// Repart au cadrage : la photo figee s'efface et la camera redemarre.
    ///
    /// Les deux sont necessaires. Sans le premier, l'ecran garde l'image de
    /// l'essai precedent ; sans le second, `camera.state` n'est plus `.ready`
    /// et le bouton reste grise sur une image morte.
    private func retry() async {
        captured = nil
        phase = .framing
        await camera.start()
    }

    private func finish() {
        camera.stop()
        onFinished()
        dismiss()
    }
}
