import Kern
import SwiftUI
import UserNotifications

/// Push-Nachrichten vom Dienst „Hörbuchwunsch“: „Hörbuch ist da“ / „noch nicht gefunden“.
@MainActor
enum Benachrichtigungen {
    static var umgebung: String {
        #if DEBUG
        return "sandbox"
        #else
        return "produktion"
        #endif
    }

    /// Fragt beim ersten Wunsch um Erlaubnis; spätere Aufrufe ändern nichts.
    static func erlaubnisHolen() async {
        let erlaubt = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if erlaubt { UIApplication.shared.registerForRemoteNotifications() }
    }

    static func geraetMelden() async {
        guard let token = UserDefaults.standard.string(forKey: "apnsToken"), let abs = geteilteSitzung.hoerbuchClient else { return }
        try? await abs.meldeGeraet(token, umgebung: umgebung)
    }

    static func geraetAbmelden() async {
        guard let token = UserDefaults.standard.string(forKey: "apnsToken"), let abs = geteilteSitzung.hoerbuchClient else { return }
        try? await abs.geraetAbmelden(token)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            // Token kann sich ändern; bei erteilter Erlaubnis bei jedem Start neu holen.
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        UserDefaults.standard.set(deviceToken.map { String(format: "%02x", $0) }.joined(), forKey: "apnsToken")
        Task { @MainActor in await Benachrichtigungen.geraetMelden() }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["absItemId"] as? String
        await MainActor.run { geteilteSitzung.sprung = id.map { .hoerbuch($0) } ?? .wuensche }
    }
}
