import XCTest
@testable import Gage

/// L'accueil montre des promesses, pas des lignes de base. Ces tests fixent
/// le regroupement des seances d'une meme semaine, et l'etat qui l'emporte
/// quand elles ne sont pas toutes au meme point.
final class ChallengeSummaryTests: XCTestCase {

    private let plan = UUID()
    private let autrePlan = UUID()

    func testLesSeancesDUnePromesseNeFontQuUnDefi() {
        let defis = ChallengeSummary.weekly(from: (0..<5).map { index in
            row(planID: plan, state: .draft, jour: index)
        })

        XCTAssertEqual(defis.count, 1, "Cinq séances promises font un seul défi")
        XCTAssertEqual(defis[0].title, "Aller à la salle 5 fois cette semaine")
        XCTAssertEqual(defis[0].sessionCount, 5)
        XCTAssertEqual(defis[0].id, plan)
    }

    func testDeuxPromessesRestentDeuxDefis() {
        let defis = ChallengeSummary.weekly(from: [
            row(planID: plan, state: .draft, jour: 0),
            row(planID: autrePlan, state: .draft, jour: 1)
        ])

        XCTAssertEqual(defis.count, 2)
    }

    /// Les objectifs crees avant les promesses hebdomadaires n'ont pas de
    /// plan : les fondre ensemble inventerait une promesse jamais prise.
    func testUneSeanceSansPlanFaitDefiSeule() {
        let defis = ChallengeSummary.weekly(from: [
            row(planID: nil, state: .committed, jour: 0),
            row(planID: nil, state: .committed, jour: 1)
        ])

        XCTAssertEqual(defis.count, 2)
    }

    /// C'est le seul etat sur lequel l'utilisateur peut encore perdre de
    /// l'argent en ne faisant rien : il doit remonter sur la carte.
    func testLEtatQuiAttendUnGesteLemporte() {
        let defis = ChallengeSummary.weekly(from: [
            row(planID: plan, state: .committed, jour: 0),
            row(planID: plan, state: .proofWindowOpen, jour: 1),
            row(planID: plan, state: .closedKept, jour: 2)
        ])

        XCTAssertEqual(defis[0].state, .proofWindowOpen)
        XCTAssertTrue(defis[0].isWaitingOnUser)
        XCTAssertEqual(defis[0].keptCount, 1)
    }

    func testLesSeancesSontTrieesEtLaMiseAdditionnee() {
        let defis = ChallengeSummary.weekly(from: [
            row(planID: plan, state: .committed, jour: 4, stakeCents: 1_000),
            row(planID: plan, state: .committed, jour: 1, stakeCents: 1_500)
        ])

        let dates = defis[0].sessions.map(\.date)
        XCTAssertEqual(dates, dates.sorted(), "Les séances se lisent dans l'ordre de la semaine")
        XCTAssertEqual(defis[0].stakeCents, 2_500)
    }

    func testLaPlusProcheEcheanceRemonte() {
        let tot = Date.now.addingTimeInterval(3_600)
        let tard = Date.now.addingTimeInterval(86_400)

        let defis = ChallengeSummary.weekly(from: [
            row(planID: plan, state: .committed, jour: 1, deadline: tard),
            row(planID: plan, state: .committed, jour: 0, deadline: tot)
        ])

        XCTAssertEqual(defis[0].deadline, tot)
    }

    // MARK: - Libelle

    func testLeTitreHebdomadaireSeLitCommeUnePhrase() {
        var plan = GoalPlan()
        plan.selectCategory("sport")
        plan.selectVariant("gym")
        plan.setTimesPerWeek(5)

        XCTAssertEqual(plan.weeklyTitle, "Aller à la salle 5 fois cette semaine")
    }

    func testLElisionEstRetireeDuLibelle() {
        let promesses = GoalCatalogue.categories.flatMap(\.variants)

        for variant in promesses {
            XCTAssertFalse(
                variant.action.hasPrefix("D'") || variant.action.hasPrefix("De "),
                "« \(variant.action) » garde la préposition de la promesse"
            )
            let initiale = String(variant.action.prefix(1))
            XCTAssertEqual(
                initiale, initiale.uppercased(),
                "« \(variant.action) » doit commencer par une majuscule"
            )
        }
    }

    // MARK: - Titre affiche

    /// Un objectif d'un seul jour doit dire quand il etait attendu : « Aller a
    /// la salle 1 fois cette semaine » ne suffit pas a comprendre un refus.
    func testLeTitreDUnObjectifUniqueNommeLeJourEtLHeure() {
        let jour = Date(timeIntervalSince1970: 1_757_000_000)
        let defi = defi(sessions: [seance(date: jour, state: .closedFailed, heure: "21 h 35")])

        XCTAssertEqual(
            defi.displayTitle,
            "Aller à la salle — \(DayLabel.lowercased(jour)) à 21 h 35"
        )
    }

    /// Sans heure convenue, le titre s'arrete au jour : l'instant du controle
    /// surprise n'appartient pas au telephone (invariant 4).
    func testSansHeureConvenueLeTitreSArreteAuJour() {
        let jour = Date(timeIntervalSince1970: 1_757_000_000)
        let defi = defi(sessions: [seance(date: jour, state: .committed, heure: nil)])

        XCTAssertEqual(defi.displayTitle, "Aller à la salle — \(DayLabel.lowercased(jour))")
    }

    /// Un objectif de la semaine garde son rythme en titre : c'est sur lui que
    /// l'argent est engage, le dater sur une seule seance le ferait disparaitre.
    func testUnObjectifDeLaSemaineGardeSaPromesseEnTitre() {
        let premier = Date(timeIntervalSince1970: 1_757_000_000)
        let defi = defi(sessions: [
            seance(date: premier, state: .committed, heure: "08 h 00"),
            seance(date: premier.addingTimeInterval(2 * 86_400), state: .committed, heure: "18 h 30")
        ])

        XCTAssertEqual(defi.displayTitle, "Aller à la salle 5 fois cette semaine")
        XCTAssertEqual(defi.kindLabel, "Ton objectif de la semaine")
    }

    /// Une fenetre ouverte est la seance qui coute de l'argent : c'est elle que
    /// la mention annonce, meme si une autre vient avant dans la semaine.
    func testLaSeanceOuverteLEmporteDansLaMention() {
        let premier = Date(timeIntervalSince1970: 1_757_000_000)
        let ouverte = premier.addingTimeInterval(2 * 86_400)
        let defi = defi(sessions: [
            seance(date: premier, state: .closedKept, heure: "08 h 00"),
            seance(date: ouverte, state: .proofWindowOpen, heure: "18 h 30")
        ])

        XCTAssertEqual(
            defi.sessionHintText,
            "Preuve attendue : \(DayLabel.lowercased(ouverte)) à 18 h 30"
        )
    }

    /// La prochaine seance s'annonce ; une semaine entierement derriere nous
    /// n'annonce plus rien, la fiche raconte le reste.
    func testLaMentionAnnonceLaProchaineSeancePuisSeTait() {
        let demain = Calendar.gage.startOfDay(for: .now).addingTimeInterval(86_400)
        let aVenir = defi(sessions: [
            seance(date: demain, state: .committed, heure: "18 h 30"),
            seance(date: demain.addingTimeInterval(86_400), state: .committed, heure: nil)
        ])

        XCTAssertEqual(
            aVenir.sessionHintText,
            "Prochaine : \(DayLabel.lowercased(demain)) à 18 h 30"
        )

        let vieux = Date(timeIntervalSince1970: 1_757_000_000)
        let passe = defi(sessions: [
            seance(date: vieux, state: .closedKept, heure: "08 h 00"),
            seance(date: vieux.addingTimeInterval(86_400), state: .closedFailed, heure: "08 h 00")
        ])

        XCTAssertNil(passe.sessionHintText)
    }

    /// Un objectif unique porte deja son moment en titre : le repeter dessous
    /// n'apprendrait rien.
    func testUnObjectifUniqueNAnnonceRienSousSonTitre() {
        let defi = defi(sessions: [seance(date: .now, state: .committed, heure: "07 h 00")])

        XCTAssertNil(defi.sessionHintText)
        XCTAssertEqual(defi.kindLabel, "Ton objectif")
    }

    /// Un objectif d'avant les promesses hebdomadaires n'a pas le suffixe de
    /// rythme : on garde son titre entier plutot que de le rogner au hasard.
    func testUnTitreSansRythmeEstGardeEntier() {
        let jour = Date(timeIntervalSince1970: 1_757_000_000)
        var defi = defi(sessions: [seance(date: jour, state: .committed, heure: nil)])
        defi = ChallengeSummary(
            id: defi.id,
            title: "Ranger mon bureau",
            proofTitle: defi.proofTitle,
            state: defi.state,
            stakeCents: 0,
            deadline: nil,
            sessions: defi.sessions
        )

        XCTAssertEqual(defi.displayTitle, "Ranger mon bureau — \(DayLabel.lowercased(jour))")
    }

    /// La promesse signee ne bouge pas : c'est elle que le consentement a
    /// enregistree, la reecriture n'est que d'affichage.
    func testLaPromesseSigneeNEstPasReecrite() {
        let defi = defi(sessions: [seance(date: .now, state: .committed, heure: "18 h 30")])

        XCTAssertEqual(defi.title, "Aller à la salle 5 fois cette semaine")
    }

    // MARK: - Utilitaires

    private func defi(sessions: [ChallengeSession]) -> ChallengeSummary {
        ChallengeSummary(
            id: UUID(),
            title: "Aller à la salle 5 fois cette semaine",
            proofTitle: "Photo sur place",
            state: sessions.first?.state ?? .draft,
            stakeCents: 1000,
            deadline: nil,
            sessions: sessions
        )
    }

    private func seance(date: Date, state: GoalState, heure: String?) -> ChallengeSession {
        ChallengeSession(id: UUID(), date: date, state: state, timeText: heure)
    }

    private func row(
        planID: UUID?,
        state: GoalState,
        jour: Int,
        stakeCents: Int = 0,
        deadline: Date? = nil
    ) -> GoalSessionRow {
        GoalSessionRow(
            goalID: UUID(),
            planID: planID,
            title: "Aller à la salle 5 fois cette semaine",
            proofTitle: "Photo sur place",
            state: state,
            date: Date(timeIntervalSince1970: 1_757_000_000 + Double(jour) * 86_400),
            timeText: "18 h 30",
            stakeCents: stakeCents,
            deadline: deadline
        )
    }
}
