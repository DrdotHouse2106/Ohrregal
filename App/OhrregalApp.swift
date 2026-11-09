import Kern
import SwiftUI

/// Gemeinsam für iPhone und CarPlay; CarPlay kann die App auch ohne iPhone-Oberfläche starten.
@MainActor let geteilterPlayer = Player()
@MainActor let geteilteSitzung = Sitzung()

@main
struct OhrregalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sitzung = geteilteSitzung
    @State private var player = geteilterPlayer

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let client = sitzung.client {
                    Hauptansicht().environment(\.client, client)
                } else {
                    Anmeldung()
                }
            }
            .environment(sitzung)
            .environment(player)
            .tint(Farben.blau)
            .preferredColorScheme(.dark)
        }
    }
}

/// Angemeldeter Server; Zugangsdaten in UserDefaults, Passwort im Schlüsselbund.
@MainActor @Observable
final class Sitzung {
    var client: NavidromeClient? { didSet { geteilterPlayer.client = client } }
    var hoerbuchClient: AudiobookshelfClient? { didSet { geteilterPlayer.hoerbuchClient = hoerbuchClient } }
    /// Ziel nach dem Antippen einer Push-Nachricht.
    var sprung: Sprung?
    /// Titel, für die gerade eine Playlist gewählt wird.
    var playlistFuer: [Titel]?
    /// Ist ein eigener Wunsch-Dienst eingerichtet? Nur dann gibt es Wünschen, Stöbern, Entdecken, Mitteilungen und Hörprotokoll.
    var dienstDa = UserDefaults.standard.bool(forKey: "dienstDa")

    /// Fragt `/wunsch-api/status` ab (ohne Anmeldung). Ohne Antwort bleibt der letzte bekannte Stand.
    func dienstPruefen() async {
        guard let basis = musikwunsch?.basis else { dienstDa = false; return }
        struct Status: Decodable { let ok: Bool }
        do {
            let (daten, antwort) = try await URLSession.shared.data(from: basis.appending(path: "status"))
            let da = (antwort as? HTTPURLResponse)?.statusCode == 200 && ((try? JSONDecoder().decode(Status.self, from: daten).ok) ?? false)
            dienstDa = da
            UserDefaults.standard.set(da, forKey: "dienstDa")
        } catch {}
    }

    enum Sprung: Equatable {
        case hoerbuch(String)
        case wuensche
        case musikwuensche
    }

    init() {
        let d = UserDefaults.standard
        if let text = d.string(forKey: "server"), let url = URL(string: text),
           let benutzer = d.string(forKey: "benutzer"), let passwort = Schluesselbund.lies("navidrome") {
            client = NavidromeClient(server: url, benutzer: benutzer, passwort: passwort)
        }
        ladeHoerbuch()
        // Hörprotokoll geht an den eigenen Server (Wunsch-Dienst), angemeldet mit dem Navidrome-Konto.
        Protokoll.geteilt.senden = { ereignisse in
            // Ohne eigenen Dienst bleibt das Protokoll auf dem iPhone.
            guard geteilteSitzung.dienstDa else { return .spaeter }
            return await geteilteSitzung.musikwunsch?.sendeEreignisse(ereignisse) ?? .spaeter
        }
        Task {
            await dienstPruefen()
            await Protokoll.geteilt.abschicken()
        }
        // Beobachter greifen im eigenen init nicht; daher hier ausdrücklich.
        geteilterPlayer.client = client
        geteilterPlayer.hoerbuchClient = hoerbuchClient
    }

    /// Audiobookshelf ist optional; ohne Zugang bleibt der Tab „Hörbücher“ leer.
    func ladeHoerbuch() {
        let d = UserDefaults.standard
        hoerbuchClient = nil
        guard let text = d.string(forKey: "absServer"), !text.isEmpty, let benutzer = d.string(forKey: "absBenutzer"),
              let passwort = Schluesselbund.lies("audiobookshelf"), let url = Adresse.aufbereiten(text) else { return }
        hoerbuchClient = AudiobookshelfClient(server: url, benutzer: benutzer.trimmingCharacters(in: .whitespacesAndNewlines),
                                              passwort: passwort.trimmingCharacters(in: .newlines))
        // Offline gehörte Stellen nachtragen, sobald der Server erreichbar ist.
        if let abs = hoerbuchClient { Task { await Offline.geteilt.nachtragen(abs) } }
    }

    func anmelden(server: String, benutzer: String, passwort: String) async throws {
        // Leerzeichen am Rand fügt die iPhone-Tastatur gern selbst an (Wortvorschläge, Einfügen) – sie führen zu „falsches Passwort“.
        let benutzer = benutzer.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwort = passwort.trimmingCharacters(in: .newlines)
        // https:// ergänzen bzw. statt http:// nehmen, Adresse der Weboberfläche (…/app) kürzen.
        guard let url = Adresse.aufbereiten(server) else { throw ServerFehler("Die Adresse ist ungültig.") }
        let text = url.absoluteString
        let neu = NavidromeClient(server: url, benutzer: benutzer, passwort: passwort)
        try await neu.ping()
        UserDefaults.standard.set(text, forKey: "server")
        UserDefaults.standard.set(benutzer, forKey: "benutzer")
        Schluesselbund.speichere(passwort, fuer: "navidrome")
        client = neu
    }

    func abmelden() {
        let abs = hoerbuchClient, dienst = musikwunsch
        Task { await Benachrichtigungen.geraetAbmelden(abs, dienst) }
        Schluesselbund.loesche("navidrome")
        client = nil
    }
}

private struct ClientSchluessel: EnvironmentKey {
    static let defaultValue = NavidromeClient(server: URL(string: "http://localhost")!, benutzer: "", passwort: "")
}

extension EnvironmentValues {
    var client: NavidromeClient {
        get { self[ClientSchluessel.self] }
        set { self[ClientSchluessel.self] = newValue }
    }
}

struct Hauptansicht: View {
    @Environment(\.scenePhase) private var phase
    @Environment(Sitzung.self) private var sitzung
    @Environment(Player.self) private var player
    @Environment(\.client) private var client
    @State private var playerOffen = false
    @State private var tab = 0
    @State private var hoerbuchPfad = NavigationPath()
    @State private var musikPfad = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { StartView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Start", systemImage: "house.fill") }
                .tag(0)
            NavigationStack(path: $musikPfad) { MusikView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Musik", systemImage: "music.note") }
                .tag(1)
            NavigationStack(path: $hoerbuchPfad) { HoerbuecherView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Hörbücher", systemImage: "books.vertical.fill") }
                .tag(2)
            NavigationStack { SucheView().ziele() }
                .miniPlayer($playerOffen)
                .tabItem { Label("Suchen", systemImage: "magnifyingglass") }
                .tag(3)
        }
        .miniPlayerInTabLeiste($playerOffen, aktiv: player.anzeige != nil)
        .sheet(isPresented: $playerOffen) { VollPlayer() }
        .sheet(isPresented: Binding(get: { sitzung.playlistFuer != nil }, set: { if !$0 { sitzung.playlistFuer = nil } })) {
            PlaylistAuswahl(titel: sitzung.playlistFuer ?? [])
        }
        .onChange(of: sitzung.sprung) { springen() }
        .onChange(of: phase) { if phase == .background { Task { await Protokoll.geteilt.abschicken() } } }
        .onAppear { springen() }
        .task(id: client.adresse("ping")) {
            player.client = client
            player.hoerbuchClient = sitzung.hoerbuchClient
        }
    }

    /// Öffnet nach einer Push-Nachricht das Hörbuch bzw. „Meine Wünsche“.
    private func springen() {
        guard let ziel = sitzung.sprung else { return }
        sitzung.sprung = nil
        if ziel == .musikwuensche {
            tab = 1
            musikPfad = NavigationPath([Ziel.musikwuensche("")])
            return
        }
        tab = 2
        var pfad = NavigationPath()
        if case .hoerbuch(let id) = ziel { pfad.append(Ziel.hoerbuch(id)) } else { pfad.append(Ziel.wuensche) }
        hoerbuchPfad = pfad
    }
}
