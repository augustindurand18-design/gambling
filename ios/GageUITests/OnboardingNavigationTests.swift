import XCTest

/// Parcours de premier lancement : connexion, puis création d'un objectif
/// jusqu'à l'engagement signé.
///
/// Les tests qui portent sur la création partent d'une application déjà
/// connectée : un test d'interface ne peut pas lire le code reçu par e-mail.
/// Le drapeau `-uiTestSignedIn` n'existe qu'en debug.
///
/// Le test capture aussi chaque écran en pièce jointe, ce qui donne un
/// comparatif avec les maquettes à chaque exécution.
final class OnboardingNavigationTests: XCTestCase {

    // MARK: - Connexion

    /// L'accueil de bienvenue ne laisse plus entrer personne sans compte :
    /// sans session, aucune requête ne passe la RLS, et `commit_goal` est
    /// réservée au rôle authenticated.
    func testCommencerDemandeUneAdresseEmail() {
        let app = XCUIApplication()
        app.launch()

        let commencer = app.buttons["Commencer"]
        XCTAssertTrue(commencer.waitForExistence(timeout: 10), "Écran d'accueil absent")
        commencer.tap()

        XCTAssertTrue(
            app.staticTexts["Ton adresse e-mail"].waitForExistence(timeout: 5),
            "L'écran de connexion ne s'est pas affiché"
        )

        let recevoir = app.buttons["Recevoir un code"]
        XCTAssertTrue(recevoir.exists, "Bouton d'envoi du code absent")
        XCTAssertFalse(recevoir.isEnabled, "Une adresse vide ne doit pas pouvoir être envoyée")

        let champ = app.textFields["email-field"]
        XCTAssertTrue(champ.exists, "Champ d'adresse absent")
        champ.tap()
        champ.typeText("alice@test.local")

        XCTAssertTrue(recevoir.isEnabled, "Une adresse plausible doit débloquer l'envoi")
        attach(app, name: "01-connexion")
    }

    /// « Se connecter » et « Commencer » mènent au même écran : côté serveur
    /// c'est le même appel, et l'utilisateur n'a pas à se souvenir s'il est
    /// déjà venu.
    func testSeConnecterMeneAuMemeEcran() {
        let app = XCUIApplication()
        app.launch()

        let seConnecter = app.buttons["Se connecter"]
        XCTAssertTrue(seConnecter.waitForExistence(timeout: 10), "Bouton de connexion absent")
        seConnecter.tap()

        XCTAssertTrue(
            app.staticTexts["Ton adresse e-mail"].waitForExistence(timeout: 5),
            "« Se connecter » doit mener au même écran que « Commencer »"
        )
    }

    // MARK: - Création d'un objectif

    func testParcoursCreationObjectif() {
        let app = launchSignedIn()

        XCTAssertTrue(
            app.staticTexts["Tes défis"].waitForExistence(timeout: 10),
            "L'accueil ne s'est pas affiché pour un utilisateur connecté"
        )
        attach(app, name: "02-accueil")

        app.buttons["Nouvel objectif"].tap()

        XCTAssertTrue(
            app.staticTexts["Combien tu veux miser ?"].waitForExistence(timeout: 5),
            "L'écran de choix de mise ne s'est pas affiché"
        )
        // Le montant est formaté avec une espace insécable : on ne compare
        // que le préfixe stable du libellé.
        let mise = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer avec")
        ).firstMatch
        XCTAssertTrue(mise.exists, "Bouton de confirmation du montant absent")
        attach(app, name: "03-choix-mise")

        mise.tap()

        // Tant qu'aucun verbe n'est choisi, la phrase reste une invitation et
        // la suite est fermée.
        XCTAssertTrue(
            app.staticTexts["Fais tourner pour composer ton objectif."].waitForExistence(timeout: 5),
            "L'écran de composition ne s'est pas affiché"
        )
        let composeContinuer = app.buttons["compose-continue"]
        XCTAssertFalse(composeContinuer.isEnabled, "La suite doit rester fermée sans objectif composé")
        attach(app, name: "04-composition-vide")

        app.buttons["Me lever"].tap()

        XCTAssertTrue(
            app.staticTexts["Je me promets de me lever à 7 h 00."].waitForExistence(timeout: 5),
            "La phrase ne s'est pas composée"
        )
        XCTAssertTrue(composeContinuer.isEnabled, "La suite doit s'ouvrir dès qu'un objectif est composé")
        attach(app, name: "05-composition")

        composeContinuer.tap()

        XCTAssertTrue(
            app.staticTexts["Que photographies-tu ?"].waitForExistence(timeout: 5),
            "L'écran de choix de preuve ne s'est pas affiché"
        )
        let proofContinuer = app.buttons["proof-continue"]
        XCTAssertFalse(proofContinuer.isEnabled, "La suite doit rester fermée sans preuve choisie")

        let preuve = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo du lit fait")
        ).firstMatch
        XCTAssertTrue(preuve.exists, "Preuve attendue absente de la liste")
        preuve.tap()
        XCTAssertTrue(proofContinuer.isEnabled, "La suite doit s'ouvrir dès qu'une preuve est choisie")
        attach(app, name: "06-choix-preuve")

        proofContinuer.tap()

        XCTAssertTrue(
            app.staticTexts["LA CONSIGNE"].waitForExistence(timeout: 5),
            "L'écran d'engagement ne s'est pas affiché"
        )
        XCTAssertTrue(
            app.staticTexts["Photo du lit fait requise"].exists,
            "La preuve choisie n'est pas rappelée à l'engagement"
        )
        attach(app, name: "07-engagement")

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
        let app = launchSignedIn()
        composerJusquALEngagement(app)

        XCTAssertTrue(
            app.buttons["Signe pour débloquer"].exists,
            "Le curseur d'engagement doit rester verrouillé tant que rien n'est signé"
        )

        app.otherElements["signature-pad"].swipeRight()

        XCTAssertTrue(
            app.buttons["Glisse pour t'engager"].waitForExistence(timeout: 5),
            "La signature n'a pas déverrouillé le curseur d'engagement"
        )
        attach(app, name: "08-engagement-signe")
    }

    /// Une fois l'engagement signé, le parcours se referme et rend la main à
    /// l'accueil.
    func testEngagementRamèneALAccueil() {
        let app = launchSignedIn()
        composerJusquALEngagement(app)

        app.otherElements["signature-pad"].swipeRight()

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
        attach(app, name: "09-confirmation")

        app.buttons["Terminer"].tap()

        XCTAssertTrue(
            app.staticTexts["Tes défis"].waitForExistence(timeout: 5),
            "L'accueil ne s'est pas réaffiché après l'engagement"
        )
    }

    // MARK: - Accueil

    func testAccueilMontreLaRegulariteEtLeProfil() {
        let app = launchSignedIn()

        XCTAssertTrue(app.staticTexts["Tes défis"].waitForExistence(timeout: 10))

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

        app.buttons["Profil et réglages"].tap()
        XCTAssertTrue(
            app.staticTexts["Plafond par objectif"].waitForExistence(timeout: 5),
            "Le profil ne s'est pas ouvert depuis l'accueil"
        )
        XCTAssertTrue(
            app.staticTexts["Se déconnecter"].exists,
            "La déconnexion doit être accessible depuis le profil"
        )
        attach(app, name: "11-profil")

        app.buttons["Fermer"].tap()
        XCTAssertTrue(
            app.staticTexts["Ta régularité"].waitForExistence(timeout: 5),
            "La fermeture du profil n'a pas ramené à l'accueil"
        )
    }

    // MARK: - Utilitaires

    /// Ouvre l'application sur une session factice. Un test d'interface ne
    /// peut pas lire le code à six chiffres reçu par e-mail ; sans ce
    /// raccourci, plus rien de ce qui suit la connexion ne serait couvert.
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSignedIn"]
        app.launch()
        return app
    }

    /// Mène de l'accueil jusqu'à l'écran d'engagement, objectif composé et
    /// preuve choisie.
    ///
    /// Chaque écran est attendu avant d'être touché : les transitions sont
    /// animées, et taper un bouton pendant l'animation donne un échec qui ne
    /// dit rien du défaut réel.
    private func composerJusquALEngagement(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nouvel = app.buttons["Nouvel objectif"]
        XCTAssertTrue(nouvel.waitForExistence(timeout: 10), "Accueil absent", file: file, line: line)
        nouvel.tap()

        let mise = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer avec")
        ).firstMatch
        XCTAssertTrue(mise.waitForExistence(timeout: 5), "Écran de mise absent", file: file, line: line)
        mise.tap()

        let verbe = app.buttons["Me lever"]
        XCTAssertTrue(verbe.waitForExistence(timeout: 5), "Écran de composition absent", file: file, line: line)
        verbe.tap()

        let composeContinuer = app.buttons["compose-continue"]
        XCTAssertTrue(composeContinuer.waitForExistence(timeout: 5), "Suite du parcours absente", file: file, line: line)
        composeContinuer.tap()

        let preuve = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo du lit fait")
        ).firstMatch
        XCTAssertTrue(preuve.waitForExistence(timeout: 5), "Écran de preuve absent", file: file, line: line)
        preuve.tap()
        app.buttons["proof-continue"].tap()

        XCTAssertTrue(
            app.staticTexts["LA CONSIGNE"].waitForExistence(timeout: 5),
            "Écran d'engagement absent", file: file, line: line
        )
        XCTAssertTrue(
            app.otherElements["signature-pad"].waitForExistence(timeout: 5),
            "Zone de signature absente", file: file, line: line
        )
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
