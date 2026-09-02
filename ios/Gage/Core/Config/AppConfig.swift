import Foundation

/// Configuration lue depuis l'Info.plist, alimentee par `Config/Secrets.xcconfig`.
///
/// Aucune cle secrete n'est embarquee : seules des cles publiques (anon key
/// Supabase protegee par RLS, cle publiable Stripe). Les cles serveur vivent
/// dans les secrets des Edge Functions.
enum AppConfig {

    enum Environment: String {
        case debug, release
    }

    static var environment: Environment {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }

    // MARK: - Supabase

    static var supabaseURL: URL {
        guard let raw = string(for: "GageSupabaseURL"), let url = URL(string: raw) else {
            fatalError("GageSupabaseURL manquant. Copie ios/Config/Secrets.example.xcconfig en Secrets.xcconfig.")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = string(for: "GageSupabaseAnonKey") else {
            fatalError("GageSupabaseAnonKey manquant. Voir ios/Config/Secrets.example.xcconfig.")
        }
        return key
    }

    // MARK: - Stripe

    static var stripePublishableKey: String? { string(for: "GageStripePublishableKey") }

    // MARK: - Observabilite (optionnelles)

    static var sentryDSN: String? { string(for: "GageSentryDSN") }
    static var telemetryDeckAppID: String? { string(for: "GageTelemetryDeckAppID") }

    // MARK: - Metadonnees

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Version des CGU en vigueur, enregistree dans chaque consentement.
    /// A incrementer a chaque modification du texte legal.
    static let termsVersion = "2026-09-v1"

    private static func string(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return value
    }
}

/// Constantes metier cote client.
///
/// Ces valeurs doivent rester alignees avec celles du serveur, qui reste
/// l'autorite : le client s'en sert uniquement pour eviter d'envoyer des
/// requetes vouees a l'echec.
enum BusinessRules {
    /// Nombre d'objectifs tenus par semaine ouvrant droit a la remise
    /// d'assiduite (25 EUR -> 5 EUR).
    static let assiduityThreshold = 3

    /// Plafonds par defaut, ajustables par l'utilisateur dans les limites
    /// acceptees a l'onboarding.
    static let defaultPerGoalCapCents = 3_000    // 30 EUR
    static let defaultMonthlyCapCents = 15_000   // 150 EUR

    /// Part de la mise reversee a l'association, en points de base.
    static let charityBps = 2_500                // 25 %

    /// Bornes de saisie d'une mise.
    static let minStakeCents = 100               // 1 EUR
}
