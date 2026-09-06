import Foundation
import Testing
@testable import Gage

/// Le delai de soumission, tel que l'application le connait.
@Suite("Fenêtre de preuve")
struct ProofWindowTests {

    @Test("Le délai de soumission vaut quinze minutes")
    func duration() {
        // La même durée vit dans app.proof_window_seconds() côté base et dans
        // MAX_CAPTURE_DELAY_SEC côté vérification. Aucune vérification
        // automatique ne détecte une divergence entre les trois : ce test
        // assène le littéral pour qu'un changement unilatéral fasse échouer
        // quelque chose plutôt que de passer inaperçu.
        #expect(ProofWindow.duration == 900)
    }

    @Test("Une fenêtre encore ouverte rend le temps qui reste")
    func remaining() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let deadline = now.addingTimeInterval(300)
        #expect(ProofWindow.remaining(until: deadline, now: now) == 300)
    }

    @Test("Une fenêtre échue ne rend aucun temps restant")
    func expired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let deadline = now.addingTimeInterval(-1)
        #expect(ProofWindow.remaining(until: deadline, now: now) == nil)
    }

    @Test("Le compte à rebours s'affiche en minutes et secondes")
    func countdown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ProofWindow.countdown(until: now.addingTimeInterval(900), now: now) == "15:00")
        #expect(ProofWindow.countdown(until: now.addingTimeInterval(64), now: now) == "01:04")
    }

    @Test("Une fenêtre échue affiche zéro plutôt que rien")
    func countdownExpired() {
        // L'écran doit pouvoir montrer que le temps est écoulé, pas se vider.
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(ProofWindow.countdown(until: now.addingTimeInterval(-30), now: now) == "00:00")
    }
}

/// Le pré-filtre embarqué, qui ne tranche jamais seul.
@Suite("Pré-filtre de preuve")
struct ProofPrecheckTests {

    @Test("Une photo ordinaire passe le pré-filtre")
    func nominal() {
        let precheck = ProofPrecheck.make(
            screenshotScore: 0.05,
            screenDetected: false,
            objectHints: ["gym", "dumbbell"]
        )
        #expect(precheck.passed)
    }

    @Test("Un écran reconnu fait échouer le pré-filtre")
    func screenDetected() {
        let precheck = ProofPrecheck.make(
            screenshotScore: 0.9,
            screenDetected: true,
            objectHints: ["computer_screen"]
        )
        #expect(!precheck.passed)
    }

    @Test("Un score élevé suffit à lever le doute, sans reconnaissance d'écran")
    func highScore() {
        let precheck = ProofPrecheck.make(
            screenshotScore: 0.8,
            screenDetected: false,
            objectHints: []
        )
        #expect(!precheck.passed)
    }

    @Test("Un pré-filtre en échec part quand même au serveur")
    func neverBlocks() {
        // Le pré-filtre est gratuit et non autoritaire : il accompagne la
        // preuve, il ne la juge pas. Un tableau de bord de voiture photographié
        // de près ressemble beaucoup à une photo d'écran, et c'est un usage
        // légitime. C'est le serveur qui achemine vers la revue humaine — et
        // là, l'utilisateur peut contester.
        let precheck = ProofPrecheck.make(
            screenshotScore: 0.95,
            screenDetected: true,
            objectHints: ["television"]
        )
        // Le verdict est transmissible : il se sérialise, donc il voyage.
        #expect((try? JSONEncoder().encode(precheck)) != nil)
        #expect(!precheck.passed)
    }

    @Test("Une analyse impossible n'est pas un soupçon")
    func inconclusive() {
        // Le serveur ne doit pas lire l'absence d'information comme une charge.
        #expect(ProofPrecheck.inconclusive.passed)
        #expect(ProofPrecheck.inconclusive.screenshotScore == 0)
    }

    @Test("Un score hors bornes est ramené dans l'intervalle")
    func clamped() {
        #expect(ProofPrecheck.make(screenshotScore: 1.4, screenDetected: false, objectHints: []).screenshotScore == 1)
        #expect(ProofPrecheck.make(screenshotScore: -0.2, screenDetected: false, objectHints: []).screenshotScore == 0)
    }

    @Test("Les clés envoyées au serveur sont celles qu'il attend")
    func encoding() throws {
        // La colonne proofs.ondevice_precheck documente exactement ces quatre
        // clés ; un renommage silencieux rendrait le champ illisible côté
        // vérification, sans qu'aucune erreur ne remonte.
        let data = try JSONEncoder().encode(
            ProofPrecheck.make(screenshotScore: 0.1, screenDetected: false, objectHints: ["bed"])
        )
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json.keys.sorted() == ["objectHints", "passed", "screenDetected", "screenshotScore"])
    }
}

/// Le chemin de stockage, impose par la policy 0018 et reverifie par la RPC.
@Suite("Chemin de stockage d'une preuve")
struct ProofStoragePathTests {

    private let user = UUID(uuidString: "AAAA1111-0000-0000-0000-000000000001")!
    private let goal = UUID(uuidString: "BBBB2222-0000-0000-0000-000000000001")!
    private let file = UUID(uuidString: "CCCC3333-0000-0000-0000-000000000001")!

    @Test("Le chemin commence par l'utilisateur, puis l'objectif")
    func shape() {
        // La policy de stockage teste (storage.foldername(name))[1] contre
        // auth.uid(), et submit_proof revérifie le préfixe complet. Un segment
        // de décalage, et l'envoi échoue sur un message serveur illisible.
        // Le littéral est en minuscules a dessein : le comparer a
        // `user.uuidString` validerait n'importe quelle casse, et c'est
        // exactement ce qui a laisse passer le bug — Postgres rend
        // `auth.uid()::text` en minuscules, Swift rend `uuidString` en
        // majuscules, et la policy compare les deux chaines telles quelles.
        let path = ProofStoragePath.make(userID: user, goalID: goal, fileID: file)
        #expect(path == "aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000001/cccc3333-0000-0000-0000-000000000001.jpg")
    }

    @Test("Le chemin est en minuscules")
    func lowercased() {
        // `auth.uid()::text` rend l'identifiant en minuscules. Une seule
        // majuscule dans le premier segment, et la policy de stockage refuse
        // l'envoi : la preuve n'atteint jamais le bucket.
        let path = ProofStoragePath.make(userID: user, goalID: goal, fileID: file)
        #expect(path == path.lowercased())
    }

    @Test("Le chemin ne porte pas le nom du bucket")
    func withoutBucket() {
        // `storage.from("proofs")` le porte déjà : l'inclure ici décalerait
        // tous les segments d'un cran.
        let path = ProofStoragePath.make(userID: user, goalID: goal, fileID: file)
        #expect(!path.hasPrefix("proofs/"))
    }

    @Test("Chaque capture reçoit un nom de fichier neuf")
    func uniquePerCapture() {
        // Aucune policy `update` n'existe sur les objets de stockage : un
        // remplacement échouerait.
        let first = ProofStoragePath.make(userID: user, goalID: goal)
        let second = ProofStoragePath.make(userID: user, goalID: goal)
        #expect(first != second)
    }

    @Test("L'empreinte porte sur les octets envoyés")
    func hashing() {
        // Le serveur compare cette valeur à ce qu'il reçoit ; hacher l'image
        // en mémoire plutôt que le JPEG final donnerait deux valeurs
        // différentes pour une même preuve.
        let data = Data("gage".utf8)
        #expect(data.sha256Hex.count == 64)
        #expect(data.sha256Hex == Data("gage".utf8).sha256Hex)
        #expect(data.sha256Hex != Data("gagf".utf8).sha256Hex)
    }
}

/// L'aiguillage entre la notification et l'ecran de capture.
@MainActor
@Suite("Routage d'une demande de preuve")
struct ProofRouterTests {

    @Test("Une notification valide ouvre l'objectif concerné")
    func valid() {
        let router = ProofRouter()
        router.handle(payload: [
            "goal_id": "BBBB2222-0000-0000-0000-000000000001",
            "proof_deadline_at": "2026-09-02T07:15:00Z",
        ])
        #expect(router.pendingGoal?.goalID.uuidString == "BBBB2222-0000-0000-0000-000000000001")
        #expect(router.pendingGoal?.deadline != nil)
    }

    @Test("Une échéance avec fraction de seconde est lue aussi")
    func fractionalSeconds() {
        // PostgREST rend l'horodatage avec ou sans fraction selon la valeur
        // stockée, et ISO8601DateFormatter n'accepte que ce qu'on lui annonce.
        let router = ProofRouter()
        router.handle(payload: [
            "goal_id": "BBBB2222-0000-0000-0000-000000000001",
            "proof_deadline_at": "2026-09-02T07:15:00.123Z",
        ])
        #expect(router.pendingGoal?.deadline != nil)
    }

    @Test("Une notification sans objectif est ignorée sans plantage")
    func malformed() {
        let router = ProofRouter()
        router.handle(payload: ["autre": "chose"])
        #expect(router.pendingGoal == nil)
    }

    @Test("Un identifiant illisible est ignoré sans plantage")
    func badIdentifier() {
        let router = ProofRouter()
        router.handle(payload: ["goal_id": "pas-un-uuid"])
        #expect(router.pendingGoal == nil)
    }

    @Test("Une échéance illisible n'empêche pas d'ouvrir l'écran")
    func missingDeadline() {
        // La fenêtre court déjà côté serveur : ne pas savoir l'afficher n'est
        // pas une raison d'empêcher l'utilisateur d'envoyer sa preuve.
        let router = ProofRouter()
        router.handle(payload: [
            "goal_id": "BBBB2222-0000-0000-0000-000000000001",
            "proof_deadline_at": "hier",
        ])
        #expect(router.pendingGoal != nil)
        #expect(router.pendingGoal?.deadline == nil)
    }

    @Test("La demande survit jusqu'à ce qu'un écran vienne la chercher")
    func survivesUntilConsumed() {
        // C'est ce qui fait marcher le démarrage à froid : au moment où
        // l'utilisateur touche la notification, aucun écran n'existe encore.
        let router = ProofRouter()
        router.handle(payload: ["goal_id": "BBBB2222-0000-0000-0000-000000000001"])
        #expect(router.pendingGoal != nil)
        #expect(router.pendingGoal != nil)

        router.clear()
        #expect(router.pendingGoal == nil)
    }
}
