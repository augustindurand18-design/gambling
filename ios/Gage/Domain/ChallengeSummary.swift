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

// MARK: - Libelle affiche

extension ChallengeSummary {

    /// Seance que le defi doit nommer : celle dont la fenetre est ouverte,
    /// sinon la prochaine a venir, sinon la derniere passee.
    ///
    /// `weekly(from:)` rend `sessions` deja trie par date, on peut donc lire
    /// « la prochaine » comme la premiere qui n'est pas derriere nous.
    var pertinentSession: ChallengeSession? {
        if let open = sessions.first(where: { $0.state == .proofWindowOpen }) { return open }
        let today = Calendar.gage.startOfDay(for: .now)
        return sessions.first { $0.date >= today } ?? sessions.last
    }

    /// L'objectif ne tient-il qu'a une seance ?
    ///
    /// Un objectif sans seance connue compte comme unique : sans rythme a
    /// annoncer, il n'y a rien a distinguer.
    var isSingleSession: Bool { sessionCount <= 1 }

    /// Titre montre a l'ecran.
    ///
    /// Une seule seance : le titre la date — « Aller a la salle — dimanche
    /// 6 septembre a 21 h 35 ». Plusieurs seances : le titre reste la
    /// promesse — « Aller a la salle 3 fois cette semaine » — parce que c'est
    /// sur ce rythme que l'argent est engage, et que le dater sur une seule
    /// de ses seances le ferait disparaitre de l'ecran.
    ///
    /// Purement de presentation dans les deux cas : `title` reste la promesse
    /// signee, celle que le consentement a enregistree.
    var displayTitle: String {
        guard isSingleSession, let session = pertinentSession else { return title }
        return "\(promisedAction) — \(moment(of: session))"
    }

    /// « Aller a la salle 3 fois cette semaine » devient « Aller a la salle ».
    ///
    /// Le rythme quitte le titre d'un objectif unique — il n'y en a pas — pour
    /// laisser la place au moment. Un objectif anterieur aux promesses
    /// hebdomadaires n'a pas ce suffixe : il est alors garde entier.
    private var promisedAction: String {
        guard let range = title.range(of: #"\s\d+ fois cette semaine$"#, options: .regularExpression)
        else { return title }
        return String(title[title.startIndex..<range.lowerBound])
    }

    /// Seance a annoncer sous le titre d'un objectif de la semaine, dont le
    /// titre ne dit que le rythme.
    ///
    /// Nul pour un objectif unique — son titre porte deja le moment — et nul
    /// quand toutes les seances sont derriere : il n'y a alors plus rien a
    /// annoncer, la fiche raconte le reste.
    var sessionHintText: String? {
        guard !isSingleSession, let session = pertinentSession else { return nil }
        if session.state == .proofWindowOpen { return "Preuve attendue : \(moment(of: session))" }
        guard session.date >= Calendar.gage.startOfDay(for: .now) else { return nil }
        return "Prochaine : \(moment(of: session))"
    }

    /// « dimanche 6 septembre a 21 h 35 », ou le jour seul quand aucune heure
    /// n'a ete convenue : l'instant du controle surprise n'appartient pas au
    /// telephone (invariant 4).
    private func moment(of session: ChallengeSession) -> String {
        let day = DayLabel.lowercased(session.date)
        guard let time = session.timeText else { return day }
        return "\(day) à \(time)"
    }

    /// Comme l'utilisateur nomme la chose : un objectif tenu un jour donne,
    /// ou une promesse qui court sur la semaine.
    var kindLabel: String {
        isSingleSession ? "Ton objectif" : "Ton objectif de la semaine"
    }
}

/// Jour ecrit en toutes lettres, d'une seule facon dans toute l'application.
enum DayLabel {

    /// « Lundi 7 septembre ».
    static func capitalized(_ date: Date) -> String {
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// « lundi 7 septembre », pour un titre ou le jour suit un tiret.
    static func lowercased(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Money.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()
}
