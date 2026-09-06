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
    @State private var phase: Phase = .framing
    @State private var now = Date.now
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case framing
        case sending
        case sent
        case failed(String)
    }

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScreenBackground {
            VStack(spacing: Theme.Spacing.medium) {
                header
                viewfinder
                action
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

        case .sent:
            VStack(spacing: Theme.Spacing.small) {
                Text("Preuve envoyée")
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)
                Text("On te dira si elle est validée.")
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.inkMuted)

                PrimaryButton(title: "Terminer", showsChevron: false) {
                    finish()
                }
            }

        case .failed(let message):
            VStack(spacing: Theme.Spacing.small) {
                Text(message)
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.failed)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Réessayer", showsChevron: false) {
                    phase = .framing
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

            phase = .sent
        } catch {
            phase = .failed(
                (error as? AppError)?.errorDescription ?? "Ta preuve n'a pas pu être envoyée."
            )
        }
    }

    private func finish() {
        camera.stop()
        onFinished()
        dismiss()
    }
}
