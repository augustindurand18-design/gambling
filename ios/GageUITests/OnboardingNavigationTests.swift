import XCTest

/// Parcours d'onboarding complet : accueil, mise, composition de l'objectif,
/// choix de la preuve, engagement signé.
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

        // Étape de composition : tant qu'aucun verbe n'est choisi, la phrase
        // reste une invitation et la suite est fermée.
        let invitation = app.staticTexts["Fais tourner pour composer ton objectif."]
        XCTAssertTrue(
            invitation.waitForExistence(timeout: 5),
            "L'écran de composition ne s'est pas affiché"
        )
        let continuer = app.buttons["Continuer"]
        XCTAssertFalse(continuer.isEnabled, "La suite doit rester fermée sans objectif composé")
        attach(app, name: "03-composition-vide")

        app.buttons["Me lever"].tap()

        XCTAssertTrue(
            app.staticTexts["Je me promets de me lever à 7 h 00."].waitForExistence(timeout: 5),
            "La phrase ne s'est pas composée"
        )
        XCTAssertTrue(continuer.isEnabled, "La suite doit s'ouvrir dès qu'un objectif est composé")
        attach(app, name: "04-composition")

        continuer.tap()

        XCTAssertTrue(
            app.staticTexts["Que photographies-tu ?"].waitForExistence(timeout: 5),
            "L'écran de choix de preuve ne s'est pas affiché"
        )
        XCTAssertFalse(continuer.isEnabled, "La suite doit rester fermée sans preuve choisie")

        let preuve = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo du lit fait")
        ).firstMatch
        XCTAssertTrue(preuve.exists, "Preuve attendue absente de la liste")
        preuve.tap()
        XCTAssertTrue(continuer.isEnabled, "La suite doit s'ouvrir dès qu'une preuve est choisie")
        attach(app, name: "05-choix-preuve")

        continuer.tap()

        XCTAssertTrue(
            app.staticTexts["LA CONSIGNE"].waitForExistence(timeout: 5),
            "L'écran d'engagement ne s'est pas affiché"
        )
        XCTAssertTrue(
            app.staticTexts["Photo du lit fait requise"].exists,
            "La preuve choisie n'est pas rappelée à l'engagement"
        )
        attach(app, name: "06-engagement")

        // Le retour ramène à l'étape précédente, preuve conservée.
        app.buttons["Retour"].tap()
        XCTAssertTrue(
            app.staticTexts["Que photographies-tu ?"].waitForExistence(timeout: 5),
            "Le bouton retour n'a pas ramené au choix de la preuve"
        )
    }

    /// La signature conditionne le geste d'engagement : sans elle, le curseur
    /// reste verrouillé. C'est la garde qui protège le consentement au débit.
    func testEngagementVerrouilleTantQueNonSigne() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Commencer"].tap()
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer avec")
        ).firstMatch.tap()

        XCTAssertTrue(app.buttons["Me lever"].waitForExistence(timeout: 5))
        app.buttons["Me lever"].tap()
        app.buttons["Continuer"].tap()

        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo du lit fait")
        ).firstMatch.tap()
        app.buttons["Continuer"].tap()

        XCTAssertTrue(app.staticTexts["LA CONSIGNE"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Signe pour débloquer"].exists,
            "Le curseur d'engagement doit rester verrouillé tant que rien n'est signé"
        )

        // Un trait dans la zone de signature déverrouille le curseur.
        let zone = app.otherElements["signature-pad"]
        XCTAssertTrue(zone.waitForExistence(timeout: 5), "Zone de signature absente")
        zone.swipeRight()

        XCTAssertTrue(
            app.buttons["Glisse pour t'engager"].waitForExistence(timeout: 5),
            "La signature n'a pas déverrouillé le curseur d'engagement"
        )
        attach(app, name: "07-engagement-signe")
    }

    /// Une fois l'engagement signé, l'application bascule sur l'accueil et
    /// n'y revient plus : l'onboarding ne se rejoue pas.
    func testEngagementMeneALAccueil() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Commencer"].tap()
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer avec")
        ).firstMatch.tap()

        XCTAssertTrue(app.buttons["Me lever"].waitForExistence(timeout: 5))
        app.buttons["Me lever"].tap()
        app.buttons["Continuer"].tap()

        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo du lit fait")
        ).firstMatch.tap()
        app.buttons["Continuer"].tap()

        let zone = app.otherElements["signature-pad"]
        XCTAssertTrue(zone.waitForExistence(timeout: 5))
        zone.swipeRight()

        // Le curseur se traverse d'un bout à l'autre : un geste court doit
        // revenir en arrière, c'est ce qui protège le débit d'un doigt posé
        // par accident.
        let curseur = app.buttons["Glisse pour t'engager"]
        XCTAssertTrue(curseur.waitForExistence(timeout: 5), "Curseur d'engagement absent")
        curseur.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: curseur.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)))

        XCTAssertTrue(
            app.staticTexts["Tu t'es engagé."].waitForExistence(timeout: 5),
            "La confirmation d'engagement ne s'est pas affichée"
        )
        attach(app, name: "08-confirmation")

        app.buttons["Terminer"].tap()

        XCTAssertTrue(
            app.staticTexts["Tes défis"].waitForExistence(timeout: 5),
            "L'accueil ne s'est pas affiché après l'engagement"
        )
        XCTAssertTrue(app.buttons["Nouvel objectif"].exists, "Création d'un nouvel objectif absente de l'accueil")
        attach(app, name: "09-accueil")

        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["Ta régularité"].waitForExistence(timeout: 5),
            "La section de régularité est absente de l'accueil"
        )
        XCTAssertTrue(
            app.otherElements["Régularité des douze dernières semaines"].exists,
            "La grille de régularité n'est pas exposée"
        )
        attach(app, name: "10-regularite")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
