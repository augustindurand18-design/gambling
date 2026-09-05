import Foundation

/// Mise en forme des montants.
///
/// Les montants circulent partout en centimes (entiers) : aucun `Double` ne
/// touche a l'argent. Ce type est le seul endroit qui les transforme en texte.
enum Money {

    /// L'application est monolingue francaise : le montant s'ecrit « 25 € »
    /// meme si le telephone est configure en anglais, sinon on afficherait
    /// « €25 » dans une phrase francaise.
    static let locale = Locale(identifier: "fr_FR")

    /// Format court affiche a l'utilisateur : « 25 € », « 12,50 € ».
    /// Les centimes ne sont montres que s'ils existent.
    static func format(cents: Int, currency: String = "EUR") -> String {
        let amount = Decimal(cents) / 100
        let fractionDigits = cents % 100 == 0 ? 0 : 2
        return amount.formatted(
            .currency(code: currency)
                .precision(.fractionLength(fractionDigits))
                .locale(locale)
        )
    }
}
