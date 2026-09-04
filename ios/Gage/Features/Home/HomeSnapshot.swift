import Foundation

/// Tout ce que l'accueil affiche, en une valeur.
///
/// L'ecran est une fonction de cette valeur : il ne va rien chercher lui-meme.
/// Le jour ou les requetes Supabase existeront, seule la fabrique changera.
struct HomeSnapshot: Equatable, Sendable {
    var challenges: [ChallengeSummary]
    var calendar: ConsistencyCalendar
    var assiduity: AssiduityStatus

    /// Aucun defi en cours : l'accueil bascule sur son etat vide.
    var isEmpty: Bool { challenges.isEmpty }
}

extension HomeSnapshot {
    /// Jeu de donnees de demonstration.
    ///
    /// Provisoire : l'application n'a pas encore de couche de donnees, aucun
    /// de ces defis n'existe en base et rien n'est debite. A remplacer par la
    /// requete des objectifs de l'utilisateur.
    static var sample: HomeSnapshot {
        let calendar = Calendar.gage
        let today = calendar.startOfDay(for: .now)

        // Historique plausible : de la regularite, quelques trous, deux
        // echecs — assez pour que la grille se lise vraiment.
        var outcomes: [Date: DayOutcome] = [:]
        let script: [Int: DayOutcome] = [
            1: .kept, 2: .kept, 4: .failed, 5: .kept, 7: .kept, 8: .kept,
            9: .kept, 11: .kept, 12: .kept, 14: .kept, 15: .failed, 16: .kept,
            18: .kept, 19: .kept, 21: .kept, 22: .kept, 24: .kept, 25: .kept,
            26: .kept, 28: .kept, 30: .kept, 31: .kept, 33: .kept, 35: .kept,
            36: .kept, 38: .failed, 39: .kept, 41: .kept, 42: .kept, 44: .kept
        ]
        for (daysAgo, outcome) in script {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            outcomes[date] = outcome
        }
        outcomes[today] = .pending

        return HomeSnapshot(
            challenges: [
                ChallengeSummary(
                    id: UUID(),
                    title: "Je me promets de me lever à 7 h 00.",
                    proofTitle: "Photo du lit fait",
                    state: .proofWindowOpen,
                    stakeCents: 2_500,
                    deadline: .now.addingTimeInterval(2_700)
                ),
                ChallengeSummary(
                    id: UUID(),
                    title: "Je me promets d'aller à la salle à 18 h 30.",
                    proofTitle: "Photo sur place",
                    state: .committed,
                    stakeCents: 1_500,
                    deadline: .now.addingTimeInterval(39_600)
                ),
                ChallengeSummary(
                    id: UUID(),
                    title: "Je me promets de faire mon bureau à 20 h 00.",
                    proofTitle: "Photo du plan de travail",
                    state: .aiVerifying,
                    stakeCents: 1_000,
                    deadline: nil
                )
            ],
            calendar: ConsistencyCalendar.build(outcomes: outcomes, reference: .now, calendar: calendar),
            assiduity: AssiduityStatus(keptThisWeek: 2)
        )
    }

    /// Compte neuf : rien n'a encore ete engage.
    static var empty: HomeSnapshot {
        HomeSnapshot(
            challenges: [],
            calendar: ConsistencyCalendar.build(outcomes: [:]),
            assiduity: AssiduityStatus(keptThisWeek: 0)
        )
    }
}
