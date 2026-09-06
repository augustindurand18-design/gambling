import CryptoKit
import Foundation

/// Le texte que l'utilisateur accepte en engageant une mise, et son empreinte.
///
/// ⚠️ **Ce texte n'a pas été relu par un juriste.** Il tient lieu de
/// rédaction de travail pour la bêta fermée. La consultation est ouverte dans
/// `CLAUDE.md` et porte sur trois points qui touchent directement ces lignes :
/// la qualification en jeu d'argent, le risque de clause pénale, et la forme
/// du consentement au débit différé.
///
/// Deux règles de rédaction viennent des décisions produit et ne doivent pas
/// bouger sans elles :
///
/// - **La somme est présentée comme un engagement, jamais comme une amende.**
///   Un texte qui parlerait de « pénalité » ou de « sanction » invite la
///   qualification de clause pénale, réductible par un juge et potentiellement
///   abusive en B2C.
/// - **Le montant, l'échéance, la part reversée et la carte utilisée figurent
///   tous dans le texte accepté.** Un consentement qui renverrait à des
///   conditions générales pour l'essentiel ne vaudrait pas grand-chose devant
///   une banque.
enum ConsentTerms {

    /// Version du texte. Toute modification de `text(for:)` doit
    /// s'accompagner d'une nouvelle version : les consentements déjà signés
    /// renvoient à la leur, et doivent rester relisables tels quels.
    static var version: String { AppConfig.termsVersion }

    struct Context {
        let goalTitle: String
        let proofInstruction: String?
        let amountCents: Int
        let charityBps: Int
        let scheduleText: String
        /// Quatre derniers chiffres de la carte enregistrée, si connue.
        let cardLast4: String?
    }

    /// Le texte exact, tel qu'affiché et tel que haché.
    ///
    /// Aucune date ni heure courante ici : le texte doit être reproductible à
    /// l'identique des mois plus tard pour que son empreinte se vérifie.
    /// L'instant d'acceptation vit à côté, dans `consents.accepted_at`.
    static func text(for context: Context) -> String {
        let amount = Money.format(cents: context.amountCents)
        let charity = Money.format(
            cents: Stake.charityShare(of: context.amountCents, bps: context.charityBps)
        )
        let share = String(format: "%g", Double(context.charityBps) / 100)

        var lines: [String] = []

        lines.append("Je m'engage sur : \(context.goalTitle).")

        if let proof = context.proofInstruction {
            lines.append("Ce que je devrai montrer : \(proof).")
        }

        lines.append("Quand : \(context.scheduleText).")

        lines.append(
            "Je mets \(amount) en jeu. Une notification me demandera ma preuve à "
                + "un moment que je ne connais pas à l'avance, et j'aurai "
                + "\(Int(ProofWindow.duration / 60)) minutes pour l'envoyer depuis "
                + "l'appareil photo de l'application."
        )

        lines.append(
            "Si ma preuve est acceptée, rien ne m'est débité. Si elle est refusée "
                + "ou si je n'en envoie aucune, j'autorise le prélèvement de "
                + "\(amount) sur ma carte enregistrée"
                + (context.cardLast4.map { ", terminant par \($0)" } ?? "")
                + ", sans nouvelle saisie de ma part."
        )

        lines.append(
            "Sur cette somme, \(charity) (\(share) %) sera reversé à l'association "
                + "que j'ai choisie. Le reste rémunère le service."
        )

        lines.append(
            "Cet engagement ne comporte aucun gain : je ne peux rien gagner, "
                + "seulement ne rien perdre."
        )

        return lines.joined(separator: "\n\n")
    }

    /// Empreinte du texte accepté.
    ///
    /// Le format est imposé par la contrainte `consents_terms_hash` en base :
    /// 64 caractères hexadécimaux minuscules.
    static func hash(of text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Texte et empreinte d'un même contexte, pour ne jamais hacher autre
    /// chose que ce qui a été montré.
    static func sealed(_ context: Context) -> (text: String, hash: String) {
        let body = text(for: context)
        return (body, hash(of: body))
    }
}
