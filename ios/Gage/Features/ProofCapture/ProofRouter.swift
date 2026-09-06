import Foundation

/// Aiguillage entre la notification et l'écran de capture.
///
/// `AppDelegate` n'est pas dans l'environnement SwiftUI : il ne peut pas
/// présenter une vue, seulement déposer ce qu'il vient de recevoir. Cet objet
/// est la boîte aux lettres entre les deux.
///
/// Il **retient** l'objectif jusqu'à ce qu'une vue vienne le chercher. C'est
/// ce qui fait marcher le démarrage à froid : quand l'utilisateur touche la
/// notification alors que l'application était fermée, le message arrive avant
/// que le moindre écran existe.
@MainActor
@Observable
final class ProofRouter {
    static let shared = ProofRouter()

    /// Objectif dont la preuve est attendue, déposé par la notification.
    private(set) var pendingGoal: PendingProof?

    init() {}

    /// Lit le contenu d'une notification APNs.
    ///
    /// Une charge utile inattendue est ignorée sans bruit : un message
    /// malformé ne doit pas faire tomber l'application, et il n'y a rien
    /// d'utile à en dire à l'utilisateur.
    func handle(payload: [AnyHashable: Any]) {
        guard
            let raw = payload["goal_id"] as? String,
            let goalID = UUID(uuidString: raw)
        else {
            Log.push.error("Notification sans objectif exploitable")
            return
        }

        // L'échéance vient du serveur. Son absence n'empêche pas d'ouvrir
        // l'écran : le compte à rebours partira de la valeur relue en base.
        let deadline = (payload["proof_deadline_at"] as? String)
            .flatMap(Self.date(fromISO:))

        pendingGoal = PendingProof(goalID: goalID, deadline: deadline)
        Log.push.info("Demande de preuve reçue")
    }

    /// Referme la demande. Appelé quand l'écran de capture se ferme, quelle
    /// qu'en soit l'issue.
    func clear() {
        pendingGoal = nil
    }

    /// PostgREST rend l'horodatage avec ou sans fraction de seconde selon la
    /// valeur stockée, et `ISO8601DateFormatter` n'accepte que ce qu'on lui a
    /// annoncé. Les deux formes sont donc essayées.
    static func date(fromISO text: String) -> Date? {
        withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// Demande de preuve en attente d'être présentée.
struct PendingProof: Identifiable, Hashable, Sendable {
    let goalID: UUID
    let deadline: Date?

    var id: UUID { goalID }
}
