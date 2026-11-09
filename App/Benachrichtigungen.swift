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
        guard let token = UserDefaults.standard.string(forKey: "apnsToken") else { return }
        do {
            // Mit Audiobookshelf-Konto über dieses, sonst mit der Navidrome-Anmeldung.
            if let abs = geteilteSitzung.hoerbuchClient {
                try await abs.meldeGeraet(token, umgebung: umgebung)
            } else if let dienst = geteilteSitzung.musikwunsch {
                try await dienst.meldeGeraet(token, umgebung: umgebung)
            } else { return }
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
        guard geteilteSitzung.hoerbuchClient != nil || geteilteSitzung.client != nil else { return "Es ist kein Server eingetragen." }
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
        // Downloads im Hintergrund wieder verbinden.
        Task { @MainActor in _ = Offline.geteilt }
        Hintergrund.registrieren()
        Hintergrund.planen()
        Task { @MainActor in
            // Token kann sich ändern; bei erteilter Erlaubnis bei jedem Start neu holen.
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Task { @MainActor in Offline.geteilt.hintergrundFertig = completionHandler }
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
        let info = response.notification.request.content.userInfo
        let id = info["absItemId"] as? String
        let musik = info["musikWunschId"] != nil
        await MainActor.run { geteilteSitzung.sprung = musik ? Sitzung.Sprung.musikwuensche : id.map { Sitzung.Sprung.hoerbuch($0) } ?? .wuensche }
    }
}
