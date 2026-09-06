import XCTest

/// Les points d'entrée du paiement dans l'interface.
///
/// Ces tests existent parce que l'écran d'enregistrement de carte a été écrit
/// avant d'être accroché à quoi que ce soit : il compilait, il était testé
/// unitairement, et il était inatteignable. Un utilisateur qui composait un
/// objectif se faisait dire « enregistre une carte » sans aucun moyen de le
/// faire.
///
/// Ils vérifient l'accessibilité, pas Stripe : la session est factice, donc
/// aucune requête ne part. Ce qui est en jeu ici, c'est qu'une porte existe.
final class PaymentNavigationTests: XCTestCase {

    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSignedIn"]
        app.launch()
        return app
    }

    /// Le profil doit proposer d'enregistrer une carte et de choisir une
    /// association. Les deux étaient des libellés figés « bientôt ».
    func testLeProfilOuvreLesReglagesDePaiement() {
        let app = launchSignedIn()

        let profil = app.buttons["Profil et réglages"]
        XCTAssertTrue(profil.waitForExistence(timeout: 10), "Bouton de profil absent")
        profil.tap()

        let carte = app.staticTexts["Moyen de paiement"]
        XCTAssertTrue(carte.waitForExistence(timeout: 5), "Ligne « Moyen de paiement » absente")

        let association = app.staticTexts["Association choisie"]
        XCTAssertTrue(association.exists, "Ligne « Association choisie » absente")

        attach(app, name: "01-profil-paiement")
    }

    /// La ligne de carte doit réellement ouvrir un écran, pas rester inerte.
    func testLaLigneCarteOuvreLEcranDEnregistrement() {
        let app = launchSignedIn()

        let profil = app.buttons["Profil et réglages"]
        XCTAssertTrue(profil.waitForExistence(timeout: 10))
        profil.tap()

        let carte = app.staticTexts["Moyen de paiement"]
        XCTAssertTrue(carte.waitForExistence(timeout: 5))
        carte.tap()

        // Le titre de l'écran d'enregistrement. Sa présence prouve que la
        // porte s'ouvre ; ce qu'il y a derrière dépend du serveur.
        XCTAssertTrue(
            app.staticTexts["Ta carte"].waitForExistence(timeout: 5),
            "L'écran d'enregistrement de carte ne s'est pas ouvert"
        )

        attach(app, name: "02-enregistrement-carte")
    }

    /// La ligne d'association doit ouvrir la liste.
    func testLaLigneAssociationOuvreLaListe() {
        let app = launchSignedIn()

        let profil = app.buttons["Profil et réglages"]
        XCTAssertTrue(profil.waitForExistence(timeout: 10))
        profil.tap()

        let association = app.staticTexts["Association choisie"]
        XCTAssertTrue(association.waitForExistence(timeout: 5))
        association.tap()

        XCTAssertTrue(
            app.navigationBars["Association"].waitForExistence(timeout: 5),
            "L'écran de choix d'association ne s'est pas ouvert"
        )

        attach(app, name: "03-choix-association")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }
}
