import Foundation
import Supabase

/// Lecture des objectifs de l'utilisateur connecte.
///
/// Les requetes nomment leurs colonnes plutot que de tout ramener : l'accueil
/// n'a pas besoin des instants de verification ni du motif de revue, et une
/// liste explicite dit aussi ce que l'ecran attend du serveur.
struct GoalsAPI: Sendable {
    static let shared = GoalsAPI()
    private let client = SupabaseClientProvider.shared

    /// Colonnes lisibles necessaires a l'accueil, plus la mise associee.
    private static let homeColumns = """
    id,title,proof_instruction,state,target_date,proof_deadline_at,\
    stakes(amount_cents,status)
    """

    /// Charge tout ce que l'accueil affiche.
    ///
    /// Une seule requete : l'accueil est le premier ecran apres le lancement,
    /// et enchainer trois allers-retours y ferait clignoter trois blocs
    /// separement.
    func loadHome(reference: Date = .now, calendar: Calendar = .gage) async throws -> HomeSnapshot {
        // `session` et non `currentSession` : le second lit un cache
        // synchrone qui peut etre vide juste apres l'ouverture de session, et
        // rend un jeton perime sans le dire. Le premier attend le stockage et
        // rafraichit si besoin.
        //
        // Sans jeton valide, la requete partirait en tant qu'`anon`, qui n'a
        // aucun droit sur les objectifs : le serveur repondrait « permission
        // denied », message juste mais illisible pour l'utilisateur.
        do {
            _ = try await client.auth.session
        } catch {
            Log.app.error("Chargement de l'accueil sans session valide")
            throw AppError.notAuthenticated
        }

        let rows: [GoalRow]
        do {
            rows = try await client
                .from("goals")
                .select(Self.homeColumns)
                .order("target_date", ascending: true)
                .execute()
                .value
        } catch {
            throw Self.mapped(error)
        }

        return HomeSnapshot(
            challenges: rows.filter { $0.state.isActive }.map(\.summary),
            calendar: ConsistencyCalendar.build(
                outcomes: Self.outcomes(from: rows, calendar: calendar),
                reference: reference,
                calendar: calendar
            ),
            assiduity: AssiduityStatus(
                keptThisWeek: Self.keptThisWeek(rows, reference: reference, calendar: calendar)
            )
        )
    }

    /// Verdict d'une journee, vu de l'utilisateur.
    ///
    /// Deux objectifs le meme jour : le manque l'emporte sur le tenu. Peindre
    /// la journee en vert alors qu'une mise a ete perdue raconterait a
    /// l'utilisateur une histoire fausse sur sa propre discipline.
    private static func outcomes(from rows: [GoalRow], calendar: Calendar) -> [Date: DayOutcome] {
        var outcomes: [Date: DayOutcome] = [:]
        for row in rows {
            guard let day = row.day(in: calendar), let outcome = row.outcome else { continue }
            outcomes[day] = Self.dominant(outcomes[day], outcome)
        }
        return outcomes
    }

    private static func dominant(_ existing: DayOutcome?, _ incoming: DayOutcome) -> DayOutcome {
        guard let existing else { return incoming }
        let severity: [DayOutcome: Int] = [.none: 0, .kept: 1, .pending: 2, .failed: 3]
        return (severity[incoming] ?? 0) > (severity[existing] ?? 0) ? incoming : existing
    }

    /// Objectifs tenus depuis lundi. Le compteur d'assiduite fera autorite
    /// cote serveur (`assiduity_weeks`) quand `weekly-assiduity` existera ;
    /// en attendant il est derive des objectifs, ce qui donne le meme chiffre
    /// tant qu'aucune semaine n'est gelee pour incident de carte.
    private static func keptThisWeek(_ rows: [GoalRow], reference: Date, calendar: Calendar) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: reference) else { return 0 }
        return rows.filter { row in
            row.outcome == .kept && (row.day(in: calendar).map(week.contains) ?? false)
        }.count
    }

    private static func mapped(_ error: Error) -> AppError {
        Log.app.error("Chargement de l'accueil: \(error.localizedDescription, privacy: .public)")
        if error is URLError { return .network }
        if error is DecodingError { return .decoding }
        return .server(message: "Impossible de charger tes défis.")
    }
}

/// Ligne renvoyee par la requete d'accueil.
private struct GoalRow: Decodable {
    let id: UUID
    let title: String
    let proofInstruction: String?
    let state: GoalState
    /// Jour vise, au format « 2026-09-10 ».
    let targetDate: String
    let proofDeadlineAt: Date?
    /// Un objectif porte au plus une mise : `stakes.goal_id` est unique,
    /// et PostgREST renvoie donc un objet et non un tableau. Un brouillon
    /// pas encore engage n'en a aucune.
    let stakes: StakeRow?

    struct StakeRow: Decodable {
        let amountCents: Int
        let status: StakeStatus

        enum CodingKeys: String, CodingKey {
            case amountCents = "amount_cents"
            case status
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, state, stakes
        case proofInstruction = "proof_instruction"
        case targetDate = "target_date"
        case proofDeadlineAt = "proof_deadline_at"
    }

    var summary: ChallengeSummary {
        ChallengeSummary(
            id: id,
            title: title,
            proofTitle: proofInstruction ?? "Preuve photo",
            state: state,
            stakeCents: stakes?.amountCents ?? 0,
            deadline: proofDeadlineAt
        )
    }

    /// Le jour vise est une date sans heure : la lire comme un instant la
    /// decalerait d'un fuseau et rangerait la case dans la mauvaise colonne.
    func day(in calendar: Calendar) -> Date? {
        var components = DateComponents()
        let parts = targetDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    var outcome: DayOutcome? {
        switch state {
        case .closedKept:
            .kept
        case .closedFailed, .chargePending, .chargeOk, .chargeFailed:
            .failed
        case .committed, .proofWindowOpen, .proofSubmitted, .aiVerifying,
             .validated, .rejected, .humanReview:
            .pending
        case .draft:
            // Un brouillon n'engage rien : il ne colore pas la grille.
            nil
        }
    }
}
