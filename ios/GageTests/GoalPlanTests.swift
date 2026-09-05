import XCTest
@testable import Gage

/// Le plan est la seule source de la phrase que l'utilisateur signe et des
/// jours sur lesquels il s'engage. Ces tests fixent la cascade qui empeche
/// une preuve de survivre a l'objectif pour lequel elle a ete choisie, et le
/// quota de jours qui empeche de promettre plus que ce qu'on programme.
final class GoalPlanTests: XCTestCase {

    // MARK: - Phrase

    func testAucunObjectifTantQueRienNestChoisi() {
        let plan = GoalPlan()
        XCTAssertEqual(plan.sentence, "Objectif non défini")
        XCTAssertTrue(plan.proofs.isEmpty, "Aucune preuve ne doit être proposée sans objectif")
    }

    func testPhraseAvecElision() {
        var plan = GoalPlan()
        plan.selectCategory("sport")
        plan.selectVariant("gym")

        XCTAssertEqual(plan.sentence, "Je me promets d'aller à la salle 3 fois par semaine.")
        XCTAssertEqual(plan.shortTitle, "La salle · 3 fois par semaine")
    }

    func testLeRythmeSeLitDansLaPhrase() {
        var plan = GoalPlan()
        plan.selectCategory("wake-up")
        plan.selectVariant("plain")
        plan.setTimesPerWeek(1)

        XCTAssertEqual(plan.sentence, "Je me promets de me lever 1 fois par semaine.")
    }

    // MARK: - Cascade

    func testChangerDeFamilleEfaceDeclinaisonEtPreuve() {
        var plan = GoalPlan()
        plan.selectCategory("sport")
        plan.selectVariant("gym")
        plan.proofID = plan.proofs[0].id

        plan.selectCategory("tidy")

        XCTAssertNil(plan.variantID, "La déclinaison ne doit pas survivre au changement de famille")
        XCTAssertNil(plan.proofID, "La preuve ne doit pas survivre au changement de famille")
        XCTAssertNil(plan.selectedProof)
    }

    func testChangerDeDeclinaisonEfaceLaPreuve() {
        var plan = GoalPlan()
        plan.selectCategory("sport")
        plan.selectVariant("gym")
        plan.proofID = plan.proofs[0].id

        plan.selectVariant("run")

        XCTAssertNil(plan.proofID)
    }

    // MARK: - Semaine

    func testOnNeCochePasPlusDeJoursQueDeSeancesPromises() {
        var plan = GoalPlan()
        plan.setTimesPerWeek(2)
        plan.toggleDay(.monday)
        plan.toggleDay(.wednesday)
        plan.toggleDay(.friday)

        XCTAssertEqual(plan.days, [.monday, .wednesday])
        XCTAssertFalse(plan.canSelectMoreDays)
        XCTAssertTrue(plan.isScheduleComplete)
    }

    func testBaisserLeRythmeRetireLesDerniersJours() {
        var plan = GoalPlan()
        plan.toggleDay(.monday)
        plan.toggleDay(.wednesday)
        plan.toggleDay(.saturday)

        plan.setTimesPerWeek(2)

        XCTAssertEqual(plan.days, [.monday, .wednesday])
        XCTAssertNil(plan.times[.saturday], "L'heure d'un jour retiré ne doit pas rester en mémoire")
    }

    func testUnJourCocheAttendSonHeureLeMatinMeme() {
        var plan = GoalPlan()
        plan.toggleDay(.monday)

        XCTAssertEqual(plan.time(for: .monday), .onTheDay)

        plan.setTime(.fixed(hour: 18, minute: 30), for: .monday)
        XCTAssertEqual(plan.time(for: .monday), .fixed(hour: 18, minute: 30))
        XCTAssertEqual(plan.time(for: .monday).text, "18 h 30")
    }

    func testUneHeureNeSePosePasSurUnJourNonCoche() {
        var plan = GoalPlan()
        plan.setTime(.fixed(hour: 8, minute: 0), for: .tuesday)

        XCTAssertEqual(plan.time(for: .tuesday), .onTheDay)
    }

    func testDecocherUnJourOublieSonHeure() {
        var plan = GoalPlan()
        plan.toggleDay(.friday)
        plan.setTime(.fixed(hour: 7, minute: 5), for: .friday)

        plan.toggleDay(.friday)

        XCTAssertTrue(plan.days.isEmpty)
        XCTAssertNil(plan.times[.friday])
    }

    func testRecapitulatifDeLaSemaine() {
        var plan = GoalPlan()
        plan.setTimesPerWeek(2)
        plan.toggleDay(.monday)
        plan.toggleDay(.thursday)
        plan.setTime(.fixed(hour: 7, minute: 0), for: .monday)

        XCTAssertEqual(plan.scheduleText, "Lundi, 7 h 00 · Jeudi, heure le matin")
    }

    func testUnPlanIncompletNestPasEngageable() {
        var plan = GoalPlan()
        plan.toggleDay(.monday)

        XCTAssertFalse(plan.isScheduleComplete, "Trois séances promises, un seul jour coché")
    }

    // MARK: - Projection sur le calendrier

    /// Un jour qui tombe aujourd'hui compte pour aujourd'hui, les autres pour
    /// leur prochaine occurrence.
    func testLesSeancesTombentSurLaProchaineOccurrence() {
        var calendar = Calendar.gage
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!

        // Mercredi 2 septembre 2026.
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 2
        let mercredi = calendar.date(from: components)!

        var plan = GoalPlan()
        plan.toggleDay(.monday)
        plan.toggleDay(.wednesday)
        plan.toggleDay(.saturday)

        let sessions = plan.sessions(from: mercredi, calendar: calendar)
        let jours = sessions.map { calendar.component(.day, from: $0.date) }

        XCTAssertEqual(sessions.map(\.day), [.monday, .wednesday, .saturday])
        XCTAssertEqual(jours, [7, 2, 5], "Lundi prochain le 7, mercredi aujourd'hui, samedi le 5")
    }

    func testAucuneSeanceSansJourChoisi() {
        XCTAssertTrue(GoalPlan().sessions().isEmpty)
    }

    // MARK: - Catalogue

    func testChaqueDeclinaisonProposeAuMoinsDeuxPreuves() {
        for category in GoalCatalogue.categories {
            XCTAssertFalse(category.variants.isEmpty, "« \(category.title) » n'a aucune déclinaison")

            for variant in category.variants {
                XCTAssertGreaterThanOrEqual(
                    variant.proofs.count, 2,
                    "« \(variant.title) » doit laisser un vrai choix de preuve"
                )
                XCTAssertEqual(
                    Set(variant.proofs.map(\.id)).count, variant.proofs.count,
                    "Identifiants de preuve dupliqués pour « \(variant.title) »"
                )
            }

            XCTAssertEqual(
                Set(category.variants.map(\.id)).count, category.variants.count,
                "Identifiants de déclinaison dupliqués dans « \(category.title) »"
            )
        }

        XCTAssertEqual(
            Set(GoalCatalogue.categories.map(\.id)).count, GoalCatalogue.categories.count,
            "Identifiants de famille dupliqués"
        )
    }
}
