import OSLog

/// Journalisation categorisee.
///
/// Regle absolue : ne jamais journaliser de donnee personnelle, de montant
/// nominatif, de token, ni de chemin de preuve. Les identifiants sont
/// acceptables, leur contenu non.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.augustindurand.gage"

    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let goal = Logger(subsystem: subsystem, category: "goal")
    static let proof = Logger(subsystem: subsystem, category: "proof")
    static let payment = Logger(subsystem: subsystem, category: "payment")
    static let push = Logger(subsystem: subsystem, category: "push")
    static let app = Logger(subsystem: subsystem, category: "app")
}
