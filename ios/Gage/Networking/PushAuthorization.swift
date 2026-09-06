import UIKit
import UserNotifications

/// Demande l'autorisation de notifier, puis enregistre l'appareil.
///
/// Sans ce déclencheur, `AppDelegate.didRegisterForRemoteNotifications` n'est
/// jamais appelé et `DeviceRegistrar` reste du code mort — ce qui était le cas
/// jusqu'ici : le squelette APNs existait, mais rien ne le mettait en marche.
///
/// L'enjeu dépasse le confort. `app.open_due_proof_windows()` refuse
/// délibérément d'ouvrir une fenêtre pour un utilisateur sans appareil
/// joignable : sans jeton enregistré, aucun contrôle ne partira jamais.
enum PushAuthorization {

    /// À appeler à chaque ouverture de session et à chaque lancement.
    ///
    /// Apple demande de rappeler `registerForRemoteNotifications()` à chaque
    /// démarrage : le jeton peut changer (restauration de sauvegarde, mise à
    /// jour du système), et le serveur doit recevoir le nouveau.
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                guard granted else {
                    Log.push.info("Notifications refusées par l'utilisateur")
                    return
                }
            } catch {
                Log.push.error("Demande d'autorisation impossible: \(error.localizedDescription)")
                return
            }

        case .denied:
            // Un refus ne se redemande pas : iOS ne réaffiche jamais l'alerte.
            // Le seul recours est un passage par les Réglages, que l'écran de
            // capture proposera le moment venu.
            Log.push.info("Notifications refusées : réglages système à ouvrir")
            return

        case .authorized, .provisional, .ephemeral:
            break

        @unknown default:
            break
        }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// L'utilisateur a-t-il coupé les notifications ?
    ///
    /// Sert à l'avertir : sans notification, il ne saura pas quand sa preuve
    /// est demandée, et sa mise est en jeu.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus == .denied
    }
}
