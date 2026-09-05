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
    id,plan_id,title,proof_instruction,state,target_date,proof_deadline_at,\
    fixed_time_local,window_start_local,\
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
            // Les brouillons apparaissent aussi : tant que Stripe n'est pas
            // branche, aucun objectif ne peut passer a `committed`, et les
            // masquer donnerait un accueil vide a quelqu'un qui vient de
            // composer son objectif.
            //
            // Les seances sont regroupees par promesse : l'utilisateur a
            // promis une semaine, pas cinq objectifs separes.
            challenges: ChallengeSummary.weekly(
                from: rows
                    .filter { $0.state.isActive || $0.state == .draft }
                    .compactMap { $0.sessionRow(in: calendar) }
            ),
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
    let planID: UUID?
    let title: String
    let proofInstruction: String?
    let state: GoalState
    /// Jour vise, au format « 2026-09-10 ».
    let targetDate: String
    let proofDeadlineAt: Date?
    /// Heure convenue, « 18:30:00 ». Nulle quand l'heure sera donnee le
    /// matin meme — le brouillon porte alors la plage de la journee.
    let fixedTimeLocal: String?
    let windowStartLocal: String?
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
        case planID = "plan_id"
        case proofInstruction = "proof_instruction"
        case targetDate = "target_date"
        case proofDeadlineAt = "proof_deadline_at"
        case fixedTimeLocal = "fixed_time_local"
        case windowStartLocal = "window_start_local"
    }

    /// Projection en seance. Une ligne sans jour lisible est ecartee : elle
    /// ne peut se ranger nulle part dans la semaine.
    func sessionRow(in calendar: Calendar) -> GoalSessionRow? {
        guard let date = day(in: calendar) else { return nil }
        return GoalSessionRow(
            goalID: id,
            planID: planID,
            title: title,
            proofTitle: proofInstruction ?? "Preuve photo",
            state: state,
            date: date,
            timeText: Self.timeText(from: fixedTimeLocal),
            stakeCents: stakes?.amountCents ?? 0,
            deadline: proofDeadlineAt
        )
    }

    /// « 18:30:00 » devient « 18 h 30 ». Sans heure convenue, rien : la fiche
    /// de detail dira que l'heure se donne le matin meme.
    private static func timeText(from local: String?) -> String? {
        guard let local else { return nil }
        let parts = local.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]) else { return nil }
        return "\(hour) h \(parts[1])"
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

// MARK: - Creation

extension GoalsAPI {

    /// Enregistre le plan de la semaine sur le compte connecte : un objectif
    /// par jour retenu.
    ///
    /// La base ne sait pas encore representer une promesse hebdomadaire — un
    /// objectif y vaut pour un jour et porte une mise. Le plan est donc
    /// projete en autant d'objectifs que de seances promises.
    ///
    /// Les objectifs sont crees en `draft` : rien n'est engage, aucune mise
    /// n'existe, aucun argent n'est en jeu. Le passage a `committed` appartient
    /// a la RPC `commit_goal`, qui exige un moyen de paiement enregistre —
    /// donc le branchement Stripe, qui n'existe pas encore.
    ///
    /// - Returns: le nombre d'objectifs ecrits.
    @discardableResult
    func createGoals(
        plan: GoalPlan,
        reference: Date = .now,
        calendar: Calendar = .gage
    ) async throws -> Int {
        guard plan.variant != nil else { throw AppError.server(message: "Objectif incomplet.") }

        let userID: UUID
        do {
            userID = try await client.auth.session.user.id
        } catch {
            Log.goal.error("Création d'objectif sans session valide")
            throw AppError.notAuthenticated
        }

        // Toutes les seances d'une meme composition partagent cet
        // identifiant : c'est lui qui permet a l'accueil de les remontrer
        // comme la promesse unique qu'elles sont.
        let planID = UUID()

        let rows = plan.sessions(from: reference, calendar: calendar).map { session in
            NewGoalRow(
                plan: plan,
                day: session.day,
                date: session.date,
                userID: userID,
                planID: planID
            )
        }

        guard !rows.isEmpty else { throw AppError.server(message: "Aucun jour choisi.") }

        do {
            try await client.from("goals").insert(rows).execute()
        } catch {
            Log.goal.error("Création d'objectifs: \(error.localizedDescription, privacy: .public)")
            if error is URLError { throw AppError.network }
            throw AppError.server(message: "Impossible d'enregistrer ton objectif.")
        }

        Log.goal.debug("Objectifs créés : \(rows.count, privacy: .public)")
        return rows.count
    }
}

/// Ligne envoyee a PostgREST pour creer un objectif.
///
/// L'etat n'est pas transmis : la valeur par defaut de la colonne vaut
/// `draft`, et la policy d'insertion n'accepte que celle-la.
///
/// L'encodage est ecrit a la main pour que **toutes** les cles soient
/// toujours presentes, valeur nulle comprise. L'encodeur synthetise, lui,
/// omet les optionnels vides : deux jours de la meme semaine — l'un a heure
/// fixe, l'autre a renseigner le matin — partiraient alors avec des jeux de
/// cles differents, et PostgREST rejette un lot heterogene
/// (`PGRST102: All object keys must match`).
private struct NewGoalRow: Encodable {
    let userID: UUID
    let planID: UUID
    let title: String
    let goalType: GoalType
    let proofInstruction: String?
    let windowMode: WindowMode
    let timezone: String
    let targetDate: String
    let fixedTimeLocal: String?
    let windowStartLocal: String?
    let windowEndLocal: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(planID, forKey: .planID)
        try container.encode(title, forKey: .title)
        try container.encode(goalType, forKey: .goalType)
        try container.encode(proofInstruction, forKey: .proofInstruction)
        try container.encode(windowMode, forKey: .windowMode)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(targetDate, forKey: .targetDate)
        try container.encode(fixedTimeLocal, forKey: .fixedTimeLocal)
        try container.encode(windowStartLocal, forKey: .windowStartLocal)
        try container.encode(windowEndLocal, forKey: .windowEndLocal)
    }

    enum CodingKeys: String, CodingKey {
        case title, timezone
        case userID = "user_id"
        case planID = "plan_id"
        case goalType = "goal_type"
        case proofInstruction = "proof_instruction"
        case windowMode = "window_mode"
        case targetDate = "target_date"
        case fixedTimeLocal = "fixed_time_local"
        case windowStartLocal = "window_start_local"
        case windowEndLocal = "window_end_local"
    }

    init(plan: GoalPlan, day: Weekday, date: Date, userID: UUID, planID: UUID) {
        self.userID = userID
        self.planID = planID
        // Toutes les seances portent le titre de la promesse, pas celui du
        // jour : c'est la promesse que l'utilisateur a prise, et l'accueil
        // les regroupe sous ce libelle.
        self.title = plan.weeklyTitle
        self.goalType = .objectScene
        self.proofInstruction = plan.selectedProof.map { "\($0.title) — \($0.subtitle)" }
        self.timezone = Self.timezone
        self.targetDate = Self.dayFormatter.string(from: date)

        switch plan.time(for: day) {
        case let .fixed(hour, minute):
            self.windowMode = .fixedTime
            self.fixedTimeLocal = String(format: "%02d:%02d:00", hour, minute)
            self.windowStartLocal = nil
            self.windowEndLocal = nil

        case .onTheDay:
            // La base exige un creneau des la creation : elle n'a pas de
            // facon de dire « heure encore inconnue ». En attendant une
            // colonne pour ca, le brouillon porte la plage de la journee,
            // que l'utilisateur remplacera par son heure le matin venu.
            // Tant que l'objectif reste en brouillon, rien n'est planifie.
            self.windowMode = .randomWindow
            self.fixedTimeLocal = nil
            self.windowStartLocal = "07:00:00"
            self.windowEndLocal = "21:00:00"
        }
    }

    private static let timezone = "Europe/Paris"

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
