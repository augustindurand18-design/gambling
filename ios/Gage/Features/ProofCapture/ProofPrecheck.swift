import Foundation
@preconcurrency import Vision

/// Pré-filtre exécuté sur l'appareil, avant l'envoi.
///
/// Il est **gratuit et non autoritaire** : il n'empêche jamais un envoi et ne
/// décide jamais qu'une preuve est fausse. Son résultat part au serveur dans
/// `proofs.ondevice_precheck`, où il devient un signal parmi d'autres — un
/// score élevé achemine vers la revue humaine, il ne rejette rien.
///
/// Cette prudence n'est pas de la timidité. Un tableau de bord de voiture
/// photographié de près ressemble beaucoup à une photo d'écran, et c'est un
/// usage parfaitement légitime. Laisser l'appareil trancher, ce serait rejeter
/// des preuves honnêtes hors de toute possibilité de contestation.
struct ProofPrecheck: Codable, Equatable, Sendable {
    /// Soupçon de photo d'écran, de 0 à 1.
    let screenshotScore: Double
    /// Un écran a-t-il été reconnu dans l'image ?
    let screenDetected: Bool
    /// Ce que Vision a cru reconnaître, pour enrichir le prompt du modèle.
    let objectHints: [String]
    /// Synthèse lisible. Faux ne bloque rien : voir la remarque ci-dessus.
    let passed: Bool

    enum CodingKeys: String, CodingKey {
        case screenshotScore, screenDetected, objectHints, passed
    }
}

extension ProofPrecheck {
    /// Au-delà, le serveur lève un signal et achemine vers la revue humaine.
    /// Le même seuil vit dans `anticheat.ts` (`ondevice_high_screenshot_score`).
    static let screenshotThreshold = 0.7

    /// Assemble le verdict à partir d'observations déjà faites.
    ///
    /// Séparée de Vision à dessein : c'est la seule partie qui contient une
    /// décision, et elle doit être testable sans caméra ni image.
    static func make(
        screenshotScore: Double,
        screenDetected: Bool,
        objectHints: [String]
    ) -> ProofPrecheck {
        let score = min(max(screenshotScore, 0), 1)
        return ProofPrecheck(
            screenshotScore: score,
            screenDetected: screenDetected,
            objectHints: objectHints,
            passed: !screenDetected && score < screenshotThreshold
        )
    }

    /// Résultat neutre, quand l'analyse n'a pas pu tourner.
    ///
    /// `passed` vaut vrai : une analyse impossible n'est pas un soupçon, et le
    /// serveur ne doit pas lire l'absence d'information comme une charge.
    static let inconclusive = ProofPrecheck(
        screenshotScore: 0,
        screenDetected: false,
        objectHints: [],
        passed: true
    )
}

// MARK: - Adaptateur Vision

/// Fait tourner Apple Vision sur une image et en tire un `ProofPrecheck`.
enum ProofVisionAnalyzer {

    /// Analyse les octets JPEG déjà produits par la capture.
    ///
    /// Ne lève jamais : une erreur de Vision rend le résultat neutre. Bloquer
    /// l'envoi parce que le pré-filtre a échoué ferait perdre une mise pour un
    /// incident technique qui n'a rien à voir avec la promesse tenue.
    static func analyze(jpegData: Data) async -> ProofPrecheck {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(data: jpegData, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Log.proof.error("Pré-filtre Vision indisponible: \(error.localizedDescription)")
            return .inconclusive
        }

        guard let observations = request.results else { return .inconclusive }

        // Vision rend des centaines de classifications ; seules les plus sûres
        // ont un sens, et seule une poignée dit quelque chose sur un écran.
        let confident = observations.filter { $0.confidence > 0.1 }

        let screenIdentifiers: Set<String> = [
            "computer_screen", "computer_monitor", "television", "screenshot",
            "laptop", "cellular_telephone", "display",
        ]

        let screenScore = confident
            .filter { screenIdentifiers.contains($0.identifier) }
            .map { Double($0.confidence) }
            .max() ?? 0

        let hints = confident
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map(\.identifier)

        return .make(
            screenshotScore: screenScore,
            screenDetected: screenScore >= screenshotThresholdForDetection,
            objectHints: Array(hints)
        )
    }

    /// Au-delà de cette confiance, on considère qu'un écran est bien présent
    /// dans l'image — et non simplement évoqué par une classification faible.
    private static let screenshotThresholdForDetection = 0.85
}
