import Foundation

/// Famille de preuve attendue. La beta ne gere que `objectScene`.
enum GoalType: String, Codable, CaseIterable, Sendable {
    /// Photo d'un objet ou d'une scene a un instant donne.
    case objectScene = "object_scene"
    /// Presence sur un lieu : geofence + photo horodatee.
    case presence
    /// Donnees d'usage du telephone (Screen Time).
    case usageData = "usage_data"
    /// Export d'une application tierce.
    case actionExport = "action_export"

    /// Disponible dans la version actuelle ?
    var isAvailable: Bool { self == .objectScene }
}

/// Mode de declenchement de la fenetre de preuve.
enum WindowMode: String, Codable, CaseIterable, Sendable {
    /// Heure precise choisie par l'utilisateur. Simple, mais la preuve est
    /// plus facile a preparer a l'avance.
    case fixedTime = "fixed_time"

    /// Instant tire au hasard par le serveur dans une plage choisie.
    /// L'utilisateur ne connait jamais l'instant a l'avance : c'est ce qui
    /// rend la photo impossible a anticiper.
    case randomWindow = "random_window"

    var localizedLabel: String {
        switch self {
        case .fixedTime: "Heure précise"
        case .randomWindow: "Contrôle surprise"
        }
    }

    var localizedExplanation: String {
        switch self {
        case .fixedTime:
            "On te demandera ta preuve à l'heure exacte que tu choisis."
        case .randomWindow:
            "On te demandera ta preuve à un moment imprévisible dans le créneau que tu choisis."
        }
    }
}

struct Goal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let userID: UUID

    var title: String
    var goalType: GoalType
    var state: GoalState
    var proofInstruction: String?
    var charityID: UUID?

    // Planification
    var windowMode: WindowMode
    var timezone: String
    var targetDate: Date
    var fixedTimeLocal: String?      // "HH:mm:ss"
    var windowStartLocal: String?
    var windowEndLocal: String?

    // Instants calcules par le serveur.
    // `windowFireAt` n'est jamais expose au client en mode surprise.
    var windowOpenedAt: Date?
    var proofDeadlineAt: Date?
    var disputeDeadlineAt: Date?
    var reviewDeadlineAt: Date?

    var committedAt: Date?
    var closedAt: Date?
    var humanReviewReason: String?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case title
        case goalType = "goal_type"
        case state
        case proofInstruction = "proof_instruction"
        case charityID = "charity_id"
        case windowMode = "window_mode"
        case timezone
        case targetDate = "target_date"
        case fixedTimeLocal = "fixed_time_local"
        case windowStartLocal = "window_start_local"
        case windowEndLocal = "window_end_local"
        case windowOpenedAt = "window_opened_at"
        case proofDeadlineAt = "proof_deadline_at"
        case disputeDeadlineAt = "dispute_deadline_at"
        case reviewDeadlineAt = "review_deadline_at"
        case committedAt = "committed_at"
        case closedAt = "closed_at"
        case humanReviewReason = "human_review_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension Goal {
    /// Temps restant pour envoyer la preuve, si la fenetre est ouverte.
    func timeRemainingForProof(now: Date = .now) -> TimeInterval? {
        guard state == .proofWindowOpen, let deadline = proofDeadlineAt else { return nil }
        let remaining = deadline.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    /// L'utilisateur peut-il encore contester ?
    func canDispute(now: Date = .now) -> Bool {
        guard state == .rejected, let deadline = disputeDeadlineAt else { return false }
        return now <= deadline
    }
}
