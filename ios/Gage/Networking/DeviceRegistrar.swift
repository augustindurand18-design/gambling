import Foundation
import UIKit

/// Enregistre le token APNs de l'appareil cote serveur.
///
/// Sans token valide, aucune demande de preuve ne peut atteindre
/// l'utilisateur : c'est un maillon critique du produit.
actor DeviceRegistrar {
    static let shared = DeviceRegistrar()

    private var lastRegisteredToken: String?

    private init() {}

    func register(apnsToken: String) async {
        guard apnsToken != lastRegisteredToken else { return }

        let device = DeviceRegistration(
            apnsToken: apnsToken,
            env: AppConfig.environment == .debug ? "sandbox" : "production",
            bundleID: Bundle.main.bundleIdentifier,
            appVersion: AppConfig.appVersion,
            osVersion: await UIDevice.current.systemVersion,
            model: await UIDevice.current.model
        )

        do {
            try await DevicesAPI.shared.upsert(device)
            lastRegisteredToken = apnsToken
            Log.push.info("Appareil enregistre pour les notifications")
        } catch {
            // Non fatal : une nouvelle tentative aura lieu au prochain lancement.
            Log.push.error("Enregistrement de l'appareil impossible: \(error.localizedDescription)")
        }
    }
}

struct DeviceRegistration: Codable, Sendable {
    let apnsToken: String
    let env: String
    let bundleID: String?
    let appVersion: String
    let osVersion: String
    let model: String

    enum CodingKeys: String, CodingKey {
        case apnsToken = "apns_token"
        case env
        case bundleID = "bundle_id"
        case appVersion = "app_version"
        case osVersion = "os_version"
        case model
    }
}
