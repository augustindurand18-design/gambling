import Foundation

/// Chargement de l'accueil.
///
/// L'ecran distingue trois etats plutot que de supposer la donnee presente :
/// un accueil vide et un accueil pas encore charge se ressemblent a l'oeil,
/// mais le premier dit « tu n'as rien engage » et le second ne dit rien.
/// Les confondre ferait croire a un utilisateur qu'il a perdu ses objectifs.
@MainActor
@Observable
final class HomeStore {

    enum State {
        case loading
        case loaded(HomeSnapshot)
        case failed(String)
    }

    private(set) var state: State

    init(state: State = .loading) {
        self.state = state
    }

    /// Charge une premiere fois. Rappelable sans risque : un ecran deja
    /// charge n'est pas recharge, pour que revenir d'une feuille modale ne
    /// fasse pas clignoter la liste.
    func loadIfNeeded() async {
        if case .loading = state {
            await reload()
        }
    }

    /// Vide ce qui a ete charge, sans rien recharger.
    ///
    /// Appele a la deconnexion : le magasin survit desormais a la session,
    /// et laisser les defis d'un compte en memoire les montrerait au suivant
    /// le temps d'un chargement.
    func reset() {
        state = .loading
    }

    func reload() async {
        #if DEBUG
        if SessionStore.isUITesting {
            state = .loaded(.sample)
            return
        }
        #endif

        do {
            state = .loaded(try await GoalsAPI.shared.loadHome())
        } catch {
            state = .failed(
                (error as? AppError)?.errorDescription ?? "Impossible de charger tes défis."
            )
        }
    }
}
