import Foundation

/// Délai laissé à l'utilisateur pour envoyer sa preuve après l'ouverture de
/// la fenêtre.
///
/// La même durée vit à trois endroits : `app.proof_window_seconds()` côté
/// base, `MAX_CAPTURE_DELAY_SEC` dans `supabase/functions/_shared/anticheat.ts`,
/// et ici. Aucune vérification automatique ne détecte une divergence — chaque
/// côté a donc un test qui assène le littéral, pour qu'un changement
/// unilatéral fasse échouer quelque chose plutôt que de passer inaperçu.
///
/// Le serveur reste seul juge : cette constante sert à afficher un compte à
/// rebours honnête, jamais à décider qu'une preuve est trop tardive. C'est
/// `submit_proof` qui tranche, et elle accorde une tolérance d'horloge que
/// l'appareil n'a pas à connaître.
enum ProofWindow {
    /// Quinze minutes.
    static let duration: TimeInterval = 900

    /// Temps restant avant l'échéance, ou `nil` si elle est passée.
    static func remaining(until deadline: Date, now: Date = .now) -> TimeInterval? {
        let remaining = deadline.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    /// Compte à rebours affichable, « 12:04 ».
    ///
    /// Une fenêtre échue rend « 00:00 » plutôt que rien : l'écran doit pouvoir
    /// montrer que le temps est écoulé, pas se vider.
    static func countdown(until deadline: Date, now: Date = .now) -> String {
        let seconds = Int(remaining(until: deadline, now: now)?.rounded(.down) ?? 0)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
