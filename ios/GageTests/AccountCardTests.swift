import Foundation
import Testing
@testable import Gage

/// Ce que l'ecran dit de la carte enregistree.
///
/// Deux champs decrivent la meme chose sans dire la meme : le moyen de
/// paiement, qui permet de debiter, et les quatre chiffres, qui ne servent
/// qu'a l'affichage et sont ecrits apres coup par le webhook. Ils divergent
/// des qu'une carte est enregistree avant que le webhook ne fonctionne — et
/// l'ecran annoncait alors « A enregistrer » a quelqu'un qui pouvait engager
/// de l'argent.
struct AccountCardTests {

    private func account(
        paymentMethod: String? = "pm_123",
        last4: String? = "4242",
        brand: String? = "visa"
    ) -> AccountState {
        AccountState(
            userID: UUID(),
            pmLast4: last4,
            pmBrand: brand,
            perGoalCapCents: 10_000,
            monthlyCapCents: 15_000,
            stakeBlockActive: false,
            stakeBlockReason: nil,
            outstandingBalanceCents: 0,
            defaultCharityID: nil,
            defaultPaymentMethodID: paymentMethod
        )
    }

    @Test("Une carte connue s'affiche avec sa marque et ses chiffres")
    func known() {
        #expect(account().cardLabel == "Visa •••• 4242")
    }

    @Test("Une carte sans quatre chiffres reste une carte enregistrée")
    func withoutLast4() {
        // Le cas qui a produit le bug : moyen de paiement present, ornement
        // absent. L'ecran ne doit pas conclure qu'il n'y a pas de carte.
        let state = account(last4: nil, brand: nil)
        #expect(state.hasCard)
        #expect(state.cardLabel == "Carte enregistrée")
        #expect(state.cardLabel != "À enregistrer")
    }

    @Test("Sans moyen de paiement, il reste une carte à enregistrer")
    func withoutCard() {
        let state = account(paymentMethod: nil, last4: nil, brand: nil)
        #expect(!state.hasCard)
        #expect(state.cardLabel == "À enregistrer")
    }

    @Test("Des chiffres sans moyen de paiement ne font pas une carte")
    func staleLast4() {
        // L'inverse du bug : des quatre chiffres restes apres le retrait du
        // moyen de paiement annonceraient une carte qui ne peut plus debiter.
        let state = account(paymentMethod: nil)
        #expect(!state.hasCard)
        #expect(state.cardLabel == "À enregistrer")
    }

    @Test("Ce qui permet d'engager est ce qui permet de débiter")
    func commitFollowsPaymentMethod() {
        // `canCommit` et `hasCard` doivent lire le meme champ : les separer
        // laisserait a nouveau l'ecran et le paiement se contredire.
        #expect(account(last4: nil).canCommit)
        #expect(!account(paymentMethod: nil).canCommit)
    }
}
