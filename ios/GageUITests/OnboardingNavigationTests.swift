import XCTest

/// Parcours d'onboarding : l'accueil mène au choix de la mise, puis au choix
/// de l'objectif.
///
/// Le test capture aussi chaque écran en pièce jointe, ce qui donne un
/// comparatif avec les maquettes à chaque exécution.
final class OnboardingNavigationTests: XCTestCase {

    func testParcoursOnboarding() {
        let app = XCUIApplication()
        app.launch()

        let commencer = app.buttons["Commencer"]
        XCTAssertTrue(commencer.waitForExistence(timeout: 10), "Écran d'accueil absent")
        attach(app, name: "01-accueil")

        commencer.tap()

        XCTAssertTrue(
            app.staticTexts["Combien tu veux miser ?"].waitForExistence(timeout: 5),
            "L'écran de choix de mise ne s'est pas affiché"
        )
        // Le montant est formaté avec une espace insécable : on ne compare
        // que le préfixe stable du libellé.
        let suite = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer avec")
        ).firstMatch
        XCTAssertTrue(suite.exists, "Bouton de confirmation du montant absent")
        attach(app, name: "02-choix-mise")

        suite.tap()

        XCTAssertTrue(
            app.staticTexts["Qu'est-ce que tu veux te forcer à faire ?"].waitForExistence(timeout: 5),
            "L'écran de choix d'objectif ne s'est pas affiché"
        )
        XCTAssertTrue(app.buttons["Se réveiller à l'heure"].exists, "Premier modèle d'objectif absent")
        attach(app, name: "03-choix-objectif")

        // Le retour ramène à l'étape précédente, montant conservé.
        app.buttons["Retour"].tap()
        XCTAssertTrue(
            suite.waitForExistence(timeout: 5),
            "Le bouton retour n'a pas ramené au choix de la mise"
        )
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
