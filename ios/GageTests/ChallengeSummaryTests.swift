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

    // MARK: - Utilitaires

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
