import UIKit
import UserNotifications

/// Point d'entree UIKit, necessaire pour recevoir le token APNs.
///
/// Les notifications sont planifiees cote serveur : c'est ce qui rend
/// l'instant de controle imprevisible en mode surprise. Aucune notification
/// locale ne doit etre utilisee pour ouvrir une fenetre de preuve.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await DeviceRegistrar.shared.register(apnsToken: token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Log.push.error("Enregistrement APNs impossible: \(error.localizedDescription)")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Une demande de preuve doit etre visible meme si l'app est au premier plan.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
