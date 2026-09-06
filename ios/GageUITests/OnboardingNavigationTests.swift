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
        // Sans ce drapeau, une session laissee dans le trousseau du simulateur
        // ouvrirait l'accueil au lieu de l'ecran de bienvenue, et le test
        // echouerait sans qu'aucun code n'ait change.
        app.launchArguments += ["-uiTestSignedOut"]
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
        // Sans ce drapeau, une session laissee dans le trousseau du simulateur
        // ouvrirait l'accueil au lieu de l'ecran de bienvenue, et le test
        // echouerait sans qu'aucun code n'ait change.
        app.launchArguments += ["-uiTestSignedOut"]
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

        // 1. La famille, en liste générique.
        XCTAssertTrue(
            app.staticTexts["Qu'est-ce que tu te promets de faire ?"].waitForExistence(timeout: 5),
            "L'écran des familles d'objectif ne s'est pas affiché"
        )
        attach(app, name: "03-familles")
        app.buttons["Faire du sport"].tap()

        // 2. La déclinaison, propre à la famille.
        XCTAssertTrue(
            app.staticTexts["Quel sport ?"].waitForExistence(timeout: 5),
            "Le sous-menu de la famille ne s'est pas affiché"
        )
        attach(app, name: "04-declinaisons")
        app.buttons["La salle"].tap()

        // 3. Le rythme et les jours.
        XCTAssertTrue(
            app.staticTexts["Je me promets d'aller à la salle"].waitForExistence(timeout: 5),
            "L'écran de planification ne s'est pas affiché"
        )
        let planContinuer = app.buttons["plan-continue"]
        XCTAssertFalse(
            planContinuer.isEnabled,
            "La suite doit rester fermée tant que les trois jours ne sont pas choisis"
        )
        attach(app, name: "05-planification-vide")

        app.buttons["day-1"].tap()
        app.buttons["day-3"].tap()
        app.buttons["day-6"].tap()
        XCTAssertTrue(planContinuer.isEnabled, "Trois jours cochés doivent ouvrir la suite")

        // Le quota est une garde, pas une suggestion : un quatrième jour ne
        // doit pas entrer alors que la promesse porte sur trois séances.
        app.buttons["day-2"].tap()
        XCTAssertFalse(
            app.buttons["day-2"].isSelected,
            "Un quatrième jour ne doit pas pouvoir être coché"
        )

        // L'heure se règle jour par jour, ou se remet au matin même.
        app.buttons["Je sais l'heure"].firstMatch.tap()
        attach(app, name: "06-planification")

        planContinuer.tap()

        // 4. La preuve. Un objectif de lieu n'en a qu'une : l'écran l'annonce
        // au lieu de la faire choisir, et la suite est ouverte d'emblée.
        XCTAssertTrue(
            app.staticTexts["Voici ce que tu photographieras"].waitForExistence(timeout: 5),
            "L'écran de preuve ne s'est pas affiché"
        )
        let proofContinuer = app.buttons["proof-continue"]
        let preuve = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo sur place")
        ).firstMatch
        XCTAssertTrue(preuve.exists, "Preuve attendue absente de l'écran")
        XCTAssertTrue(
            proofContinuer.isEnabled,
            "Une preuve unique est retenue d'office : la suite ne doit pas attendre un tap"
        )
        attach(app, name: "07-choix-preuve")

        proofContinuer.tap()

        // 5. La mise, une fois la promesse connue.
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
        attach(app, name: "08-choix-mise")

        mise.tap()

        // 6. L'engagement.
        XCTAssertTrue(
            app.staticTexts["LA CONSIGNE"].waitForExistence(timeout: 5),
            "L'écran d'engagement ne s'est pas affiché"
        )
        XCTAssertTrue(
            app.staticTexts["Je me promets d'aller à la salle 3 fois cette semaine."].exists,
            "La promesse n'est pas rappelée à l'engagement"
        )
        XCTAssertTrue(
            app.staticTexts["Photo sur place requise"].exists,
            "La preuve choisie n'est pas rappelée à l'engagement"
        )
        attach(app, name: "09-engagement")

        // Le retour ramène à l'étape précédente, mise conservée.
        app.buttons["Retour"].tap()
        XCTAssertTrue(
            app.staticTexts["Combien tu veux miser ?"].waitForExistence(timeout: 5),
            "Le bouton retour n'a pas ramené au choix de la mise"
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
        attach(app, name: "10-engagement-signe")
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
        attach(app, name: "11-confirmation")

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
        attach(app, name: "12-regularite")

        app.buttons["Profil et réglages"].tap()
        XCTAssertTrue(
            app.staticTexts["Plafond par objectif"].waitForExistence(timeout: 5),
            "Le profil ne s'est pas ouvert depuis l'accueil"
        )
        XCTAssertTrue(
            app.staticTexts["Se déconnecter"].exists,
            "La déconnexion doit être accessible depuis le profil"
        )
        attach(app, name: "13-profil")

        app.buttons["Fermer"].tap()
        XCTAssertTrue(
            app.staticTexts["Ta régularité"].waitForExistence(timeout: 5),
            "La fermeture du profil n'a pas ramené à l'accueil"
        )
    }

    /// Un defi s'ouvre sur sa fiche : la promesse de la semaine, ses seances,
    /// ce qui est en jeu.
    func testUnDefiSouvreSurSaFiche() {
        let app = launchSignedIn()

        let defi = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "fois cette semaine")
        ).firstMatch
        XCTAssertTrue(defi.waitForExistence(timeout: 10), "Aucun défi hebdomadaire sur l'accueil")
        attach(app, name: "14-accueil-defis-hebdo")

        defi.tap()

        XCTAssertTrue(
            app.staticTexts["Ton défi"].waitForExistence(timeout: 5),
            "La fiche du défi ne s'est pas ouverte"
        )
        // Les titres de section s'affichent en capitales.
        XCTAssertTrue(
            app.staticTexts["TES SÉANCES"].exists,
            "La fiche doit lister les séances de la semaine"
        )
        XCTAssertTrue(
            app.staticTexts["CE QUE TU RISQUES"].exists,
            "La fiche doit dire ce qui est en jeu"
        )
        attach(app, name: "15-fiche-defi")

        app.buttons["Fermer"].tap()
        XCTAssertTrue(
            app.staticTexts["Tes défis"].waitForExistence(timeout: 5),
            "La fermeture de la fiche n'a pas ramené à l'accueil"
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

        let famille = app.buttons["Faire du sport"]
        XCTAssertTrue(famille.waitForExistence(timeout: 5), "Écran des familles absent", file: file, line: line)
        famille.tap()

        let declinaison = app.buttons["La salle"]
        XCTAssertTrue(declinaison.waitForExistence(timeout: 5), "Sous-menu absent", file: file, line: line)
        declinaison.tap()

        let planContinuer = app.buttons["plan-continue"]
        XCTAssertTrue(planContinuer.waitForExistence(timeout: 5), "Écran de planification absent", file: file, line: line)
        app.buttons["day-1"].tap()
        app.buttons["day-3"].tap()
        app.buttons["day-6"].tap()
        planContinuer.tap()

        let preuve = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Photo sur place")
        ).firstMatch
        XCTAssertTrue(preuve.waitForExistence(timeout: 5), "Écran de preuve absent", file: file, line: line)
        preuve.tap()
        app.buttons["proof-continue"].tap()

        let mise = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Continuer avec")
        ).firstMatch
        XCTAssertTrue(mise.waitForExistence(timeout: 5), "Écran de mise absent", file: file, line: line)
        mise.tap()

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
