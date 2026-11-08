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
        do {
            try await abs.meldeGeraet(token, umgebung: umgebung)
            UserDefaults.standard.removeObject(forKey: "pushFehler")
        } catch {
            UserDefaults.standard.set("Anmeldung beim Wunsch-Dienst: \(error.localizedDescription)", forKey: "pushFehler")
        }
    }

    /// Schaltet Mitteilungen ein und beschreibt den Stand in einem Satz (für „Mitteilungen“ im Profilmenü).
    static func einschaltenUndPruefen() async -> String {
        await erlaubnisHolen()
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .denied: return "Mitteilungen sind für Ohrregal ausgeschaltet. Bitte unter Einstellungen → Mitteilungen → Ohrregal einschalten."
        case .authorized, .provisional, .ephemeral: break
        default: return "Mitteilungen sind noch nicht erlaubt."
        }
        // Kurz warten, bis iOS das Token geliefert hat.
        for _ in 0..<10 where UserDefaults.standard.string(forKey: "apnsToken") == nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        if let fehler = UserDefaults.standard.string(forKey: "pushFehler") { return fehler }
        guard UserDefaults.standard.string(forKey: "apnsToken") != nil else { return "iOS hat noch keine Adresse für Mitteilungen geliefert. Bitte später noch einmal versuchen." }
        guard geteilteSitzung.hoerbuchClient != nil else { return "Audiobookshelf ist nicht eingetragen." }
        await geraetMelden()
        return UserDefaults.standard.string(forKey: "pushFehler") ?? "Mitteilungen sind eingeschaltet. Du bekommst Bescheid, wenn ein Hörbuch da ist."
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
        UserDefaults.standard.removeObject(forKey: "pushFehler")
        Task { @MainActor in await Benachrichtigungen.geraetMelden() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set("iOS: \(error.localizedDescription)", forKey: "pushFehler")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["absItemId"] as? String
        await MainActor.run { geteilteSitzung.sprung = id.map { .hoerbuch($0) } ?? .wuensche }
    }
}
