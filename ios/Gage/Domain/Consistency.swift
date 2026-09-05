import Foundation

/// Ce qu'une journee a produit, du point de vue de l'utilisateur.
///
/// La nuance qui compte est entre « rien ce jour-la » et « non tenu » : la
/// premiere n'est pas un echec et ne doit pas etre peinte comme tel.
enum DayOutcome: String, Sendable, CaseIterable {
    /// Aucun objectif ce jour-la.
    case none
    /// Objectif tenu.
    case kept
    /// Objectif non tenu.
    case failed
    /// Objectif engage, verdict pas encore rendu.
    case pending
}

struct ConsistencyDay: Identifiable, Hashable, Sendable {
    let date: Date
    let outcome: DayOutcome
    /// Un jour a venir se distingue d'un jour vide : on n'y a pas encore
    /// echoue, la case doit rester neutre et sans relief.
    let isFuture: Bool

    var id: Date { date }
}

/// Grille de regularite : une colonne par semaine, une ligne par jour.
struct ConsistencyCalendar: Equatable, Sendable {
    /// Semaines de la plus ancienne a la plus recente. Chaque semaine
    /// contient exactement sept jours, du lundi au dimanche.
    let weeks: [[ConsistencyDay]]

    var days: [ConsistencyDay] { weeks.flatMap { $0 } }
    var keptCount: Int { days.filter { $0.outcome == .kept }.count }
    var failedCount: Int { days.filter { $0.outcome == .failed }.count }

    /// Nombre de jours engages sur la periode, verdict rendu ou non.
    var engagedCount: Int { days.filter { $0.outcome != .none }.count }

    /// Serie en cours : jours tenus consecutifs en remontant depuis le
    /// dernier jour engage. Les journees sans objectif ne cassent pas la
    /// serie — ne rien s'etre promis n'est pas un echec.
    var currentStreak: Int {
        var streak = 0
        for day in days.reversed() where !day.isFuture {
            switch day.outcome {
            case .kept: streak += 1
            case .failed: return streak
            case .pending, .none: continue
            }
        }
        return streak
    }

    /// Construit la grille des `weekCount` dernieres semaines.
    ///
    /// - Parameters:
    ///   - outcomes: verdicts connus, indexes par jour (l'heure est ignoree).
    ///   - reference: jour courant, dernier jour affiche de la grille.
    static func build(
        outcomes: [Date: DayOutcome],
        weekCount: Int = 12,
        reference: Date = .now,
        calendar: Calendar = .gage
    ) -> ConsistencyCalendar {
        let today = calendar.startOfDay(for: reference)

        // La grille se lit en colonnes de semaines completes : elle demarre
        // au lundi, meme si cela affiche quelques jours anterieurs a la
        // periode demandee.
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today),
              let start = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: thisWeek.start)
        else {
            return ConsistencyCalendar(weeks: [])
        }

        let normalized = Dictionary(
            outcomes.map { (calendar.startOfDay(for: $0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        var weeks: [[ConsistencyDay]] = []
        for week in 0..<weekCount {
            var days: [ConsistencyDay] = []
            for weekday in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start) else { continue }
                days.append(
                    ConsistencyDay(
                        date: date,
                        outcome: normalized[date] ?? .none,
                        isFuture: date > today
                    )
                )
            }
            weeks.append(days)
        }
        return ConsistencyCalendar(weeks: weeks)
    }
}

/// Avancement vers la remise d'assiduite.
///
/// Formule volontairement exprimee en remise et jamais en penalite : le
/// tarif de reference est 25 EUR, l'utilisateur descend a 5 EUR en tenant
/// ses objectifs. Voir `docs/architecture.md`.
struct AssiduityStatus: Equatable, Sendable {
    let keptThisWeek: Int
    var threshold: Int = BusinessRules.assiduityThreshold

    var isDiscountEarned: Bool { keptThisWeek >= threshold }
    var remaining: Int { max(0, threshold - keptThisWeek) }

    /// Progression bornee a 1, pour la barre.
    var progress: Double {
        guard threshold > 0 else { return 1 }
        return min(1, Double(keptThisWeek) / Double(threshold))
    }
}

extension Calendar {
    /// Calendrier de l'application : semaine commencant le lundi, comme
    /// partout en France. Sans ce reglage la grille demarrerait le dimanche
    /// et les colonnes ne correspondraient pas aux semaines d'assiduite.
    static var gage: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Money.locale
        calendar.firstWeekday = 2
        return calendar
    }
}
