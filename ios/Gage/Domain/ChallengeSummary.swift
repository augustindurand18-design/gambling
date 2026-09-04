import Foundation

/// Defi tel qu'il apparait sur l'accueil.
///
/// Vue condensee d'un `Goal` et de sa `Stake` : l'accueil n'a besoin ni des
/// instants calcules par le serveur ni des metadonnees de verification, et
/// les charger tous rendrait la liste lente pour rien. La projection sera
/// faite par la requete le jour ou les donnees viendront de Supabase.
struct ChallengeSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Promesse composee par l'utilisateur, telle qu'il l'a signee.
    let title: String
    /// Preuve qu'il s'est engage a fournir.
    let proofTitle: String
    let state: GoalState
    let stakeCents: Int
    /// Echeance affichable. Jamais l'instant du controle surprise, qui ne
    /// doit pas etre lisible par le client.
    let deadline: Date?

    var isWaitingOnUser: Bool { state.awaitsUserAction }
}
