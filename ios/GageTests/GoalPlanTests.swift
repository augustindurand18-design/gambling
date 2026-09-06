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

        XCTAssertEqual(plan.sentence, "Je me promets d'aller à la salle 3 fois cette semaine.")
        XCTAssertEqual(plan.shortTitle, "La salle · 3 fois cette semaine")
    }

    func testLeRythmeSeLitDansLaPhrase() {
        var plan = GoalPlan()
        plan.selectCategory("wake-up")
        plan.selectVariant("plain")
        plan.setTimesPerWeek(1)

        XCTAssertEqual(plan.sentence, "Je me promets de me lever 1 fois cette semaine.")
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

    func testUneFamilleADeclinaisonUniqueLaRetientDOffice() {
        var plan = GoalPlan()
        plan.selectCategory("wake-up")

        XCTAssertEqual(
            plan.variantID, "plain",
            "Une famille sans alternative ne doit pas faire passer par un écran de choix"
        )
        XCTAssertFalse(plan.proofs.isEmpty, "Les preuves doivent être disponibles dans la foulée")
    }

    func testUneFamilleAPlusieursDeclinaisonsNenRetientAucune() {
        var plan = GoalPlan()
        plan.selectCategory("sport")

        XCTAssertNil(plan.variantID, "Le choix reste à l'utilisateur dès qu'il y a une alternative")
    }

    func testChangerDeDeclinaisonEfaceLaPreuve() {
        var plan = GoalPlan()
        plan.selectCategory("sport")
        plan.selectVariant("gym")
        plan.proofID = plan.proofs[0].id

        plan.selectVariant("run")

        XCTAssertNil(plan.proofID)
    }

    // MARK: - Heure

    func testUnReveilExigeUneHeureDesLaCreation() {
        var plan = GoalPlan()
        plan.selectCategory("wake-up")
        plan.toggleDay(.monday)

        XCTAssertTrue(plan.requiresFixedTime)
        XCTAssertTrue(
            plan.time(for: .monday).isFixed,
            "Un réveil ne peut pas se renseigner le matin même : l'heure est la promesse"
        )

        plan.setTime(.onTheDay, for: .monday)
        XCTAssertTrue(
            plan.time(for: .monday).isFixed,
            "« Le matin même » doit être refusé, pas seulement masqué à l'écran"
        )
    }

    func testAilleursLHeureResteFacultative() {
        var plan = GoalPlan()
        plan.selectCategory("sport")
        plan.selectVariant("gym")
        plan.toggleDay(.monday)

        XCTAssertFalse(plan.requiresFixedTime)
        XCTAssertFalse(
            plan.time(for: .monday).isFixed,
            "Aller à la salle n'impose pas de connaître l'heure à l'avance"
        )
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

    func testPromettreSeptSeancesCocheLaSemaineEntiere() {
        var plan = GoalPlan()
        plan.setTimesPerWeek(7)

        XCTAssertEqual(
            plan.days, Set(Weekday.allCases),
            "Sept séances sur sept jours ne laissent rien à choisir"
        )
        XCTAssertTrue(plan.isScheduleComplete)
        XCTAssertFalse(plan.canSelectMoreDays)
    }

    func testPasserASeptConserveLesHeuresDejaChoisies() {
        var plan = GoalPlan()
        plan.toggleDay(.monday)
        plan.setTime(.fixed(hour: 18, minute: 30), for: .monday)

        plan.setTimesPerWeek(7)

        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(
            plan.time(for: .monday), .fixed(hour: 18, minute: 30),
            "Cocher le reste de la semaine ne doit pas écraser une heure déjà réglée"
        )
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

    /// Le nombre de preuves varie d'un objectif a l'autre : un lieu se prouve
    /// par la seule photo sur place, un rangement par deux cadrages. On exige
    /// donc au moins une preuve, jamais un quota — tenir un quota obligerait a
    /// reintroduire les preuves faibles retirees a l'audit du 2026-09-05.
    func testChaqueDeclinaisonProposeAuMoinsUnePreuve() {
        for category in GoalCatalogue.categories {
            XCTAssertFalse(category.variants.isEmpty, "« \(category.title) » n'a aucune déclinaison")

            for variant in category.variants {
                XCTAssertFalse(
                    variant.proofs.isEmpty,
                    "« \(variant.title) » ne propose aucune preuve"
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

    /// Aucune preuve ne repose sur le fait de se photographier : c'est la
    /// donnee la plus sensible qu'on puisse demander tous les jours, et aucun
    /// objectif n'en depend depuis l'audit du 2026-09-05.
    func testAucunePreuveNeDemandeUnSelfie() {
        for category in GoalCatalogue.categories {
            for variant in category.variants {
                for proof in variant.proofs {
                    XCTAssertFalse(
                        proof.title.localizedCaseInsensitiveContains("selfie"),
                        "« \(variant.title) » redemande un selfie : \(proof.title)"
                    )
                }
            }
        }
    }
}
