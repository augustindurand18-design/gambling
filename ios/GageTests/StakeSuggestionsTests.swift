import Testing
@testable import Gage

@Suite("Montants proposes a la mise")
struct StakeSuggestionsTests {

    @Test("La roue va de 5 EUR au plafond, par pas de 5 EUR")
    func spansStepToCap() {
        let stakes = BusinessRules.suggestedStakes(upTo: BusinessRules.defaultPerGoalCapCents)

        #expect(stakes.first == BusinessRules.stakeStepCents)
        #expect(stakes.last == BusinessRules.defaultPerGoalCapCents)
        #expect(stakes.contains(BusinessRules.defaultStakeCents))
        #expect(zip(stakes, stakes.dropFirst()).allSatisfy { $1 - $0 == BusinessRules.stakeStepCents })
    }

    @Test("Aucun montant propose ne depasse le plafond")
    func neverExceedsCap() {
        for cap in [500, 1_700, 3_000, 10_000] {
            #expect(BusinessRules.suggestedStakes(upTo: cap).allSatisfy { $0 <= cap })
        }
    }

    @Test("Un plafond inferieur au pas ne propose que lui-meme")
    func capBelowStep() {
        #expect(BusinessRules.suggestedStakes(upTo: 100) == [100])
    }

    @Test("Les montants ronds s'affichent sans centimes")
    func wholeAmountsHideCents() {
        #expect(Money.format(cents: 10_000).contains("100"))
        #expect(!Money.format(cents: 10_000).contains(","))
        #expect(Money.format(cents: 1_250).contains(","))
    }
}
