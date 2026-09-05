import Foundation

/// Une seance d'un defi : un jour, son heure, son etat.
///
/// C'est ce que la base appelle un objectif. L'utilisateur, lui, n'en a
/// promis qu'un pour la semaine : les seances ne se montrent que dans le
/// detail du defi.
struct ChallengeSession: Identifiable, Hashable, Sendable {
    /// Identifiant de l'objectif en base.
    let id: UUID
    let date: Date
    let state: GoalState
    /// « 18 h 30 », ou `nil` quand l'heure sera donnee le matin meme.
    let timeText: String?
}

/// Ligne ramenee par la requete d'accueil : un objectif, donc une seance.
struct GoalSessionRow: Hashable, Sendable {
    let goalID: UUID
    /// Promesse a laquelle la seance appartient. Nul pour les objectifs
    /// crees avant que les promesses hebdomadaires existent.
    let planID: UUID?
    let title: String
    let proofTitle: String
    let state: GoalState
    let date: Date
    let timeText: String?
    let stakeCents: Int
    let deadline: Date?
}

/// Defi tel qu'il apparait sur l'accueil.
///
/// Une promesse hebdomadaire, pas une seance : « aller a la salle 5 fois
/// cette semaine » est une seule carte, meme si la base la range en cinq
/// objectifs. Les cinq sont dans `sessions`, pour la fiche de detail.
struct ChallengeSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Promesse composee par l'utilisateur, telle qu'il l'a signee.
    let title: String
    /// Preuve qu'il s'est engage a fournir.
    let proofTitle: String
    /// Etat le plus avance de la semaine : celui qui demande un geste
    /// l'emporte, parce que c'est le seul qui coute de l'argent si personne
    /// ne bouge.
    let state: GoalState
    let stakeCents: Int
    /// Echeance affichable. Jamais l'instant du controle surprise, qui ne
    /// doit pas etre lisible par le client.
    let deadline: Date?
    var sessions: [ChallengeSession] = []

    var isWaitingOnUser: Bool { state.awaitsUserAction }

    /// Seances promises et seances deja tenues, pour la fiche de detail.
    var sessionCount: Int { sessions.count }
    var keptCount: Int { sessions.filter { $0.state == .closedKept }.count }
}

extension ChallengeSummary {

    /// Regroupe les seances par promesse.
    ///
    /// Une seance sans `planID` fait defi a elle seule : c'est le cas des
    /// objectifs crees avant que les promesses hebdomadaires existent, et il
    /// vaut mieux les montrer seuls que de les fondre a tort dans un groupe.
    static func weekly(from rows: [GoalSessionRow]) -> [ChallengeSummary] {
        var order: [UUID] = []
        var groups: [UUID: [GoalSessionRow]] = [:]

        for row in rows {
            let key = row.planID ?? row.goalID
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }

        return order.compactMap { key -> ChallengeSummary? in
            guard let group = groups[key]?.sorted(by: { $0.date < $1.date }),
                  let leading = group.max(by: { rank($0.state) < rank($1.state) })
            else { return nil }

            return ChallengeSummary(
                id: key,
                title: leading.title,
                proofTitle: leading.proofTitle,
                state: leading.state,
                // Somme des mises de la semaine. Le jour ou une promesse ne
                // portera plus qu'une seule mise, ce total vaudra cette mise.
                stakeCents: group.reduce(0) { $0 + $1.stakeCents },
                deadline: group.compactMap(\.deadline).min(),
                sessions: group.map {
                    ChallengeSession(id: $0.goalID, date: $0.date, state: $0.state, timeText: $0.timeText)
                }
            )
        }
        .sorted { ($0.sessions.first?.date ?? .distantFuture) < ($1.sessions.first?.date ?? .distantFuture) }
    }

    /// Ce qui doit l'emporter quand les seances d'une semaine ne sont pas
    /// dans le meme etat : d'abord ce qui attend un geste, puis ce qui est en
    /// cours, puis les brouillons, et enfin ce qui est clos.
    private static func rank(_ state: GoalState) -> Int {
        if state.awaitsUserAction { return 3 }
        if state.isActive { return 2 }
        if state == .draft { return 1 }
        return 0
    }
}
