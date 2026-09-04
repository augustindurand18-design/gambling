import XCTest
@testable import Gage

/// La composition d'un objectif est la seule source de la phrase que
/// l'utilisateur signe. Ces tests la fixent, ainsi que la cascade qui
/// empeche une preuve de survivre a l'objectif pour lequel elle a ete choisie.
final class GoalCompositionTests: XCTestCase {

    func testAucunObjectifTantQueLaRoueNaPasBouge() {
        let composition = GoalComposition()
        XCTAssertFalse(composition.isGoalChosen)
        XCTAssertEqual(composition.sentence, "Fais tourner pour composer ton objectif.")
        XCTAssertTrue(composition.proofs.isEmpty, "Aucune preuve ne doit être proposée sans objectif")
    }

    func testPhraseSansComplement() {
        var composition = GoalComposition()
        composition.selectVerb(indexOfVerb("wake-up"))

        XCTAssertEqual(composition.sentence, "Je me promets de me lever à 7 h 00.")
        XCTAssertEqual(composition.shortTitle, "Me lever à 7 h 00")
    }

    func testPhraseAvecComplementEtElision() {
        var composition = GoalComposition()
        composition.selectVerb(indexOfVerb("go"))

        XCTAssertEqual(composition.sentence, "Je me promets d'aller à la salle à 7 h 00.")
        XCTAssertEqual(composition.shortTitle, "Aller à la salle à 7 h 00")
    }

    func testHeureSansZeroInitialEtMinutesSurDeuxChiffres() {
        var composition = GoalComposition()
        composition.selectVerb(indexOfVerb("do"))
        composition.hour = 18
        composition.minute = 5

        XCTAssertEqual(composition.timeText, "18 h 05")
        XCTAssertEqual(composition.sentence, "Je me promets de faire mon lit à 18 h 05.")
    }

    func testChangerDeVerbeEfaceComplementEtPreuve() {
        var composition = GoalComposition()
        composition.selectVerb(indexOfVerb("go"))
        composition.selectComplement(2)
        composition.proofID = composition.proofs[0].id

        composition.selectVerb(indexOfVerb("do"))

        XCTAssertEqual(composition.complementIndex, 0)
        XCTAssertNil(composition.proofID, "La preuve ne doit pas survivre au changement d'objectif")
        XCTAssertNil(composition.selectedProof)
    }

    func testChangerDeComplementEfaceLaPreuve() {
        var composition = GoalComposition()
        composition.selectVerb(indexOfVerb("go"))
        composition.proofID = composition.proofs[0].id

        composition.selectComplement(1)

        XCTAssertNil(composition.proofID)
    }

    func testChaqueObjectifProposeAuMoinsDeuxPreuves() {
        for verb in GoalCatalogue.verbs where verb.isChosen {
            for complement in verb.complements {
                XCTAssertGreaterThanOrEqual(
                    complement.proofs.count, 2,
                    "« \(verb.label) \(complement.label) » doit laisser un vrai choix de preuve"
                )
                XCTAssertEqual(
                    Set(complement.proofs.map(\.id)).count, complement.proofs.count,
                    "Identifiants de preuve dupliqués pour « \(complement.label) »"
                )
            }
        }
    }

    private func indexOfVerb(_ id: String) -> Int {
        guard let index = GoalCatalogue.verbs.firstIndex(where: { $0.id == id }) else {
            XCTFail("Verbe \(id) absent du catalogue")
            return 0
        }
        return index
    }
}
