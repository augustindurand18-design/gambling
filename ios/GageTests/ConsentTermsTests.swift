import Foundation
import Testing
@testable import Gage

/// Le texte que l'utilisateur accepte, et son empreinte.
///
/// Ces tests ne jugent pas la qualite juridique du texte — ce n'est pas leur
/// role, et la consultation reste ouverte. Ils verrouillent trois choses
/// mecaniques dont depend sa valeur de preuve : l'empreinte porte sur ce qui
/// a ete montre, le texte est reproductible a l'identique des mois plus tard,
/// et il enonce lui-meme tout ce qui engage.
@Suite("Texte de consentement")
struct ConsentTermsTests {

    private func context(
        amountCents: Int = 1000,
        cardLast4: String? = "4242"
    ) -> ConsentTerms.Context {
        ConsentTerms.Context(
            goalTitle: "Aller à la salle 3 fois par semaine",
            proofInstruction: "Photo de la salle — machines visibles",
            amountCents: amountCents,
            charityBps: 2500,
            scheduleText: "lundi, mercredi et vendredi",
            cardLast4: cardLast4
        )
    }

    // MARK: - L'empreinte

    @Test("L'empreinte a le format qu'exige la base")
    func hashFormat() {
        // La contrainte `consents_terms_hash` impose 64 caracteres
        // hexadecimaux minuscules ; un format different ferait echouer
        // l'insertion au moment de l'engagement, donc au pire moment.
        let hash = ConsentTerms.sealed(context()).hash
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test("L'empreinte porte sur le texte exactement affiché")
    func hashMatchesText() {
        let sealed = ConsentTerms.sealed(context())
        #expect(sealed.hash == ConsentTerms.hash(of: sealed.text))
    }

    @Test("Le texte est reproductible à l'identique")
    func reproducible() {
        // C'est ce qui donne sa valeur à l'empreinte : le jour où quelqu'un
        // conteste, on doit pouvoir régénérer le texte et retrouver le même
        // hash. Une date courante glissée dans le texte le rendrait
        // invérifiable.
        #expect(ConsentTerms.sealed(context()).hash == ConsentTerms.sealed(context()).hash)
    }

    @Test("Changer le montant change l'empreinte")
    func amountChangesHash() {
        // Sans ça, un consentement à 5 € couvrirait un débit à 100 €.
        #expect(ConsentTerms.sealed(context(amountCents: 500)).hash
            != ConsentTerms.sealed(context(amountCents: 10_000)).hash)
    }

    // MARK: - Ce que le texte doit dire

    @Test("Le montant engagé figure en toutes lettres")
    func statesAmount() {
        // Comparé via `Money.format` plutôt qu'en dur : le français insère
        // une espace insécable étroite avant l'euro, et un montant rond perd
        // ses décimales. Un littéral testerait le formateur, pas le texte.
        let text = ConsentTerms.text(for: context(amountCents: 1500))
        #expect(text.contains(Money.format(cents: 1500)))
    }

    @Test("La carte débitée est nommée")
    func statesCard() {
        // Un consentement au débit qui ne dit pas sur quelle carte ne vaut pas
        // grand-chose devant une banque.
        #expect(ConsentTerms.text(for: context()).contains("4242"))
    }

    @Test("La part reversée à l'association est chiffrée")
    func statesCharityShare() {
        let text = ConsentTerms.text(for: context(amountCents: 1000))
        #expect(text.contains(Money.format(cents: 250)))
        #expect(text.contains("25 %"))
    }

    @Test("Aucun délai de contestation n'est promis")
    func statesNoDisputeWindow() {
        // La fenetre de 48 heures a ete retiree (2026-09-06). Promettre un
        // recours qui n'existe plus serait faire signer un texte faux, sur
        // le point meme qui autorise un prelevement.
        let text = ConsentTerms.text(for: context())
        #expect(!text.contains("48 heures"))
        #expect(!text.contains("contester"))
        #expect(text.contains("j'autorise le prélèvement"))
    }

    @Test("Le délai de soumission annoncé est celui du serveur")
    func statesProofWindow() {
        // Annoncer un délai différent de celui que `submit_proof` applique
        // serait une promesse non tenue, sur le point qui coûte de l'argent.
        let minutes = Int(ProofWindow.duration / 60)
        #expect(ConsentTerms.text(for: context()).contains("\(minutes) minutes"))
    }

    @Test("Le texte dit qu'il n'y a rien à gagner")
    func statesNoWinnings() {
        // C'est l'argument central pour ne pas tomber sous la qualification de
        // jeu d'argent : pas de hasard, pas de gain espéré.
        let text = ConsentTerms.text(for: context())
        #expect(text.contains("aucun gain"))
    }

    @Test("Le texte ne parle jamais de pénalité")
    func neverPenalty() {
        // Décision du 2026-09-02 : la somme est un engagement, jamais une
        // amende. Le vocabulaire de la sanction invite la qualification de
        // clause pénale, réductible par un juge et potentiellement abusive
        // en B2C.
        let text = ConsentTerms.text(for: context()).lowercased()
        for mot in ["pénalité", "penalite", "amende", "sanction", "punition"] {
            #expect(!text.contains(mot), "Le texte ne doit pas employer « \(mot) »")
        }
    }

    @Test("Sans carte connue, le texte reste cohérent")
    func withoutCard() {
        // L'écran peut s'afficher avant que le profil n'ait remonté les quatre
        // chiffres. Le texte doit rester lisible, pas afficher un trou.
        let text = ConsentTerms.text(for: context(cardLast4: nil))
        #expect(!text.contains("terminant par"))
        #expect(text.contains("ma carte enregistrée"))
    }
}
