import Foundation
import Supabase

/// Etat d'authentification de l'application.
///
/// La session Supabase fait autorite, et elle est restauree depuis le
/// trousseau au lancement : l'aiguillage part donc de `.loading` et non de
/// `.signedOut`, sinon l'utilisateur deja connecte verrait l'ecran d'accueil
/// clignoter avant de basculer.
@MainActor
@Observable
final class SessionStore {

    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(userID: UUID)
    }

    private(set) var state: State = .loading

    /// Suit les changements de session pour toute la duree de vie de l'app.
    /// Le flux emet toujours une `initialSession`, ce qui sort de `.loading`
    /// meme quand personne n'est connecte.
    func observe() async {
        #if DEBUG
        if Self.isUITestingSignedIn {
            state = .signedIn(userID: Self.uiTestingUserID)
            return
        }
        #endif

        for await (_, session) in SupabaseClientProvider.shared.auth.authStateChanges {
            state = session.map { .signedIn(userID: $0.user.id) } ?? .signedOut
        }
    }

    func signOut() async {
        do {
            try await AuthAPI.shared.signOut()
        } catch {
            // L'ecoute de `authStateChanges` remettra l'etat au clair ; rien
            // a faire de plus ici que de le consigner.
            Log.app.error("Déconnexion impossible: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if DEBUG
    /// Les tests d'interface ne peuvent pas lire le code recu par e-mail. Ce
    /// drapeau leur ouvre l'application deja connectee, pour continuer a
    /// couvrir la navigation qui vient apres. Compile uniquement en debug :
    /// il n'existe pas dans un binaire distribue.
    static let uiTestingArgument = "-uiTestSignedIn"

    static let uiTestingUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private static var isUITestingSignedIn: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }
    #endif
}
