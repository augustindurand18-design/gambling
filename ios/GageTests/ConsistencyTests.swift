import XCTest
@testable import Gage

/// La grille de regularite est lue d'un coup d'oeil : une case mal placee ou
/// mal coloriee raconte a l'utilisateur une histoire fausse sur sa propre
/// discipline. Ces tests fixent le decoupage et le sens des couleurs.
final class ConsistencyCalendarTests: XCTestCase {

    /// Mercredi 2 septembre 2026, pour que la grille soit deterministe.
    private let reference = DateComponents(
        calendar: .gage, timeZone: TimeZone(identifier: "Europe/Paris"),
        year: 2026, month: 9, day: 2
    ).date!

    private var calendar: Calendar {
        var calendar = Calendar.gage
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    func testLaGrilleADouzeSemainesCompletes() {
        let grid = ConsistencyCalendar.build(outcomes: [:], reference: reference, calendar: calendar)

        XCTAssertEqual(grid.weeks.count, 12)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 }, "Chaque semaine doit avoir sept jours")
    }

    func testChaqueSemaineCommenceUnLundi() {
        let grid = ConsistencyCalendar.build(outcomes: [:], reference: reference, calendar: calendar)

        for week in grid.weeks {
            XCTAssertEqual(
                calendar.component(.weekday, from: week[0].date), 2,
                "La première case d'une colonne doit être un lundi"
            )
        }
    }

    func testLaDerniereSemaineContientLeJourDeReference() {
        let grid = ConsistencyCalendar.build(outcomes: [:], reference: reference, calendar: calendar)
        let last = grid.weeks[grid.weeks.count - 1]

        XCTAssertTrue(
            last.contains { calendar.isDate($0.date, inSameDayAs: reference) },
            "La dernière colonne doit contenir aujourd'hui"
        )
    }

    func testLesJoursAVenirSontMarquesCommeTels() {
        let grid = ConsistencyCalendar.build(outcomes: [:], reference: reference, calendar: calendar)
        let future = grid.days.filter(\.isFuture)

        // Mercredi : jeudi, vendredi, samedi et dimanche restent a venir.
        XCTAssertEqual(future.count, 4)
        XCTAssertTrue(future.allSatisfy { $0.date > reference })
    }

    func testLesVerdictsSontPlacesSurLeBonJour() {
        let hier = calendar.date(byAdding: .day, value: -1, to: reference)!
        let avantHier = calendar.date(byAdding: .day, value: -2, to: reference)!

        let grid = ConsistencyCalendar.build(
            outcomes: [hier: .kept, avantHier: .failed],
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(grid.keptCount, 1)
        XCTAssertEqual(grid.failedCount, 1)
        XCTAssertEqual(grid.days.first { calendar.isDate($0.date, inSameDayAs: hier) }?.outcome, .kept)
        XCTAssertEqual(grid.days.first { calendar.isDate($0.date, inSameDayAs: avantHier) }?.outcome, .failed)
    }

    func testLHeureDuVerdictNInfluencePasSaCase() {
        // Un verdict rendu a 23 h doit tomber sur son propre jour, pas le suivant.
        let hierSoir = calendar.date(byAdding: .hour, value: -3, to: reference)!.addingTimeInterval(-79_200)

        let grid = ConsistencyCalendar.build(
            outcomes: [hierSoir: .kept],
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(grid.keptCount, 1)
    }

    func testUneJourneeSansObjectifNeCassePasLaSerie() {
        let jours = (1...4).map { calendar.date(byAdding: .day, value: -$0, to: reference)! }
        // Tenu, rien, tenu, tenu -> la journee vide ne compte pas.
        let grid = ConsistencyCalendar.build(
            outcomes: [jours[0]: .kept, jours[2]: .kept, jours[3]: .kept],
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(grid.currentStreak, 3)
    }

    func testUnEchecCasseLaSerie() {
        let jours = (1...3).map { calendar.date(byAdding: .day, value: -$0, to: reference)! }
        let grid = ConsistencyCalendar.build(
            outcomes: [jours[0]: .kept, jours[1]: .failed, jours[2]: .kept],
            reference: reference,
            calendar: calendar
        )

        XCTAssertEqual(grid.currentStreak, 1)
    }
}

/// La remise d'assiduite est le levier tarifaire du produit : elle doit se
/// declencher au seuil exact, et jamais s'exprimer en penalite.
final class AssiduityStatusTests: XCTestCase {

    func testLaRemiseSObtientAuSeuil() {
        XCTAssertFalse(AssiduityStatus(keptThisWeek: BusinessRules.assiduityThreshold - 1).isDiscountEarned)
        XCTAssertTrue(AssiduityStatus(keptThisWeek: BusinessRules.assiduityThreshold).isDiscountEarned)
    }

    func testLeResteAFaireNeDevientJamaisNegatif() {
        let status = AssiduityStatus(keptThisWeek: BusinessRules.assiduityThreshold + 5)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.progress, 1)
    }

    func testLaProgressionEstBorneeAUn() {
        XCTAssertEqual(AssiduityStatus(keptThisWeek: 0).progress, 0)
        XCTAssertEqual(AssiduityStatus(keptThisWeek: 100).progress, 1)
    }
}
