import XCTest

/// Test de fumée : l'application démarre sans planter.
///
/// Volontairement minimal tant que l'interface n'est pas dessinée. Il couvre
/// tout de même un risque réel : la configuration est lue au démarrage et
/// une valeur manquante fait échouer le lancement.
final class LaunchTests: XCTestCase {

    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "L'application n'a pas atteint le premier plan"
        )
    }
}
