import Foundation

/// Modele d'objectif propose a l'utilisateur.
///
/// Catalogue embarque pour l'instant : il servira aussi bien a l'onboarding
/// qu'a la creation d'objectifs, et passera cote serveur le jour ou la liste
/// devra evoluer sans mise a jour de l'app.
///
/// `goalType` porte l'information de disponibilite : `GoalType.isAvailable`
/// dit si la brique de verification correspondante existe deja.
struct GoalTemplate: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let goalType: GoalType

    var isAvailable: Bool { goalType.isAvailable }
}

extension GoalTemplate {
    /// Modeles proposes a l'onboarding, dans l'ordre d'affichage.
    static let onboarding: [GoalTemplate] = [
        GoalTemplate(id: "wake-up", title: "Se réveiller à l'heure", goalType: .objectScene),
        GoalTemplate(id: "gym", title: "Aller à la salle", goalType: .presence),
        GoalTemplate(id: "tiktok", title: "Moins d'1h de TikTok", goalType: .usageData)
    ]

    /// Emplacements vides affiches sous la liste : les modeles a venir.
    static let onboardingPlaceholderCount = 3
}
